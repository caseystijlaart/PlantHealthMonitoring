"""convert_old_logs.py

Converts the raw CSV log files in datasets/old_logs/ into rows that match the
features_for_edge_impulse.csv schema, then appends them to that file.

Risk is derived from the plant's actual soil moisture preference band (pLow /
pMid / pHigh) parsed from recommendation_summary, so thresholds are per-plant
rather than global.  This mirrors PlantRuleProfile::soilMoistureThresholds in
PlantTypes.hpp.

Run this script once whenever you have new old_logs to absorb.  Re-run
export_for_tinyml.py afterward if you want a fresh Edge Impulse upload.

Output: data/features_for_edge_impulse.csv  (appended in-place)
"""

import re
from pathlib import Path

import numpy as np
import pandas as pd

# ── Paths ─────────────────────────────────────────────────────────────────────

ROOT      = Path(__file__).resolve().parent
LOGS_DIR  = ROOT / "../../../datasets/old_logs"
EDGE_FILE = ROOT / "data" / "features_for_edge_impulse.csv"

# ── PlantRuleProfile soil moisture thresholds (mirrors PlantTypes.hpp) ────────
#
# MetricThresholds layout: {lowMax, midMin, midMax, highMin, highMax}
#
# Risk mapping relative to the plant's preference band:
#   soil < band_min              → risk 2 (HIGH_STRESS  — too dry)
#   band_min <= soil <= band_max → risk 0 (HEALTHY      — in preferred range)
#   soil > band_max              → risk 1 (MODERATE     — too wet, not critical)
#
# Thresholds match prototype-non-local/include/PlantTypes.hpp defaults.

SOIL_THRESHOLDS = {
    # preference: (lowMax, midMin, midMax, highMin, highMax)
    "pLow":  (28.0, 33.0, 55.0, 60.0, 90.0),   # same default — low-moisture plants
    "pMid":  (28.0, 33.0, 55.0, 60.0, 90.0),   # Aglaonema default
    "pHigh": (28.0, 40.0, 70.0, 75.0, 90.0),   # high-moisture plants
}

WATERING_SPIKE = 8.0    # soil % rise between two readings = user watered
HISTORY_WINDOW = 4      # rolling window (logs are 2-h apart → 4 samples ≈ 8 h)

# ── 1. Load all log files ─────────────────────────────────────────────────────

csv_files = sorted(LOGS_DIR.glob("*.csv"))
if not csv_files:
    raise FileNotFoundError(f"No CSV files found in {LOGS_DIR}")

frames = []
for f in csv_files:
    try:
        frames.append(pd.read_csv(f))
    except Exception as e:
        print(f"  Warning: skipping {f.name}: {e}")

raw = pd.concat(frames, ignore_index=True)
print(f"Loaded {len(raw)} rows from {len(csv_files)} log files")

# ── 2. Normalise column names ─────────────────────────────────────────────────

raw = raw.rename(columns={
    "soil_moisture_pct":    "soil_now",
    "temperature_c":        "temp_now",
    "humidity_pct":         "humidity_now",
    "light_level_pct":      "light_now",
    "timestamp_utc":        "created_at",
})

keep = ["plant_label", "soil_now", "temp_now", "humidity_now",
        "light_now", "created_at"]
if "recommendation_summary" in raw.columns:
    keep.append("recommendation_summary")

raw = raw[keep].copy()
raw["ts"]   = pd.to_datetime(raw["created_at"], utc=True)
raw["unix"] = raw["ts"].astype(np.int64) // 10**9
raw = raw.sort_values(["plant_label", "unix"]).reset_index(drop=True)

# ── 3. Parse soil preference band from recommendation_summary ────────────────
#
# Log rows look like: "... prefs=[soil:pMid,temp:pMid,...] ..."
# Fall back to pMid if the column is missing or the pattern doesn't match.

_PREF_RE = re.compile(r"soil:(pLow|pMid|pHigh)")

def parse_soil_pref(summary: str) -> str:
    if not isinstance(summary, str):
        return "pMid"
    m = _PREF_RE.search(summary)
    return m.group(1) if m else "pMid"

if "recommendation_summary" in raw.columns:
    raw["soil_pref"] = raw["recommendation_summary"].apply(parse_soil_pref)
else:
    raw["soil_pref"] = "pMid"

# ── 4. Feature engineering (per plant) ───────────────────────────────────────

def engineer_group(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy().reset_index(drop=True)
    soil = df["soil_now"].values
    n    = len(soil)

    moisture_mean  = np.zeros(n)
    moisture_delta = np.zeros(n)
    moisture_slope = np.zeros(n)
    dry_duration   = np.zeros(n)

    # dry_threshold per row — use the midMin of that row's preference band
    dry_thresholds = df["soil_pref"].map(
        lambda p: SOIL_THRESHOLDS.get(p, SOIL_THRESHOLDS["pMid"])[1]  # midMin
    ).values

    dry_streak = 0

    for i in range(n):
        win_start = max(0, i - HISTORY_WINDOW + 1)
        window    = soil[win_start : i + 1]

        moisture_mean[i]  = window.mean()
        moisture_delta[i] = soil[i] - soil[i - 1] if i > 0 else 0.0
        if len(window) >= 2:
            moisture_slope[i] = (window[-1] - window[0]) / (len(window) - 1)

        if soil[i] < dry_thresholds[i]:
            dry_streak += 1
        else:
            dry_streak = 0

        if dry_streak >= 2:
            oldest_dry_idx  = i - dry_streak + 1
            elapsed_sec     = df["unix"].iloc[i] - df["unix"].iloc[oldest_dry_idx]
            dry_duration[i] = elapsed_sec / 3600.0

    df["moisture_mean"]  = moisture_mean
    df["moisture_delta"] = moisture_delta
    df["moisture_slope"] = moisture_slope
    df["soil_x_slope"]   = df["soil_now"].values * moisture_slope
    df["dry_duration"]   = dry_duration

    hour = df["ts"].dt.hour
    dow  = df["ts"].dt.dayofweek

    df["hour_of_day"] = hour
    df["day_of_week"]  = dow
    df["hour_sin"] = np.sin(2 * np.pi * hour / 24.0)
    df["hour_cos"] = np.cos(2 * np.pi * hour / 24.0)
    df["dow_sin"]  = np.sin(2 * np.pi * dow  / 7.0)
    df["dow_cos"]  = np.cos(2 * np.pi * dow  / 7.0)

    return df


# ── 5. Derive labels ──────────────────────────────────────────────────────────

def _clip01(x: float) -> float:
    return float(np.clip(x, 0.0, 1.0))


def derive_risk(df: pd.DataFrame) -> pd.Series:
    """
    Multi-signal stress score that mirrors generate_training_data.py so the
    ML classifier has a meaningful label that requires all 12 features to
    predict — not just soil_now.

    The soil thresholds that define "low_soil" and "drying" are scaled to the
    plant's preference band (pLow / pMid / pHigh) so a moisture-loving plant
    is stressed at 50% while a drought-tolerant plant is healthy at the same
    reading.

      stress > 0.62  → risk 2 (HIGH_STRESS)
      stress > 0.34  → risk 1 (MODERATE_STRESS)
      else           → risk 0 (HEALTHY)
    """
    risks = []

    for _, row in df.iterrows():
        pref = row.get("soil_pref", "pMid")
        _, band_min, band_max, _, _ = SOIL_THRESHOLDS.get(pref, SOIL_THRESHOLDS["pMid"])
        band_range = band_max - band_min  # e.g. 22 for pMid (33–55)

        soil  = row["soil_now"]
        slope = row["moisture_slope"]
        dry_h = row["dry_duration"]
        temp  = row["temp_now"]
        hum   = row["humidity_now"]
        light = row["light_now"]

        # How far below the preferred minimum — 0 when at band_min, 1 when fully dry
        low_soil     = _clip01((band_min + band_range * 0.3 - soil) / (band_range * 0.3))
        drying_trend = _clip01((-slope) / 4.0)
        dryness_accum = _clip01(dry_h / 3.0)

        temp_factor     = _clip01((temp - 20) / 15)
        humidity_factor = _clip01((60 - hum) / 40)
        light_factor    = _clip01((light - 200) / 700)
        evap_effect     = 0.45 * temp_factor + 0.30 * humidity_factor + 0.25 * light_factor

        soil_drying_interaction = low_soil * drying_trend
        evap_dry_interaction    = evap_effect * dryness_accum
        soil_evap_interaction   = low_soil * evap_effect

        stress = (
            0.22 * low_soil
            + 0.18 * drying_trend
            + 0.16 * dryness_accum
            + 0.14 * evap_effect
            + 0.14 * soil_drying_interaction
            + 0.10 * evap_dry_interaction
            + 0.06 * soil_evap_interaction
        )
        stress = float(np.clip(stress, 0.0, 1.2))

        risks.append(2 if stress > 0.62 else (1 if stress > 0.34 else 0))

    return pd.Series(risks, index=df.index)


def derive_anomaly(temp: pd.Series, humidity: pd.Series, light: pd.Series) -> pd.Series:
    """Mirrors the anomaly flag in generate_training_data.py."""
    return (((humidity < 20) & (temp > 32)) | ((light < 70) & (temp > 34))).astype(int)


def derive_recovering(delta: pd.Series, slope: pd.Series) -> pd.Series:
    """Mirrors the recovering flag in generate_training_data.py."""
    return ((delta > 4) & (slope > 1.0)).astype(int)


# ── 6. Process per plant ──────────────────────────────────────────────────────

result_frames = []

for label, group in raw.groupby("plant_label"):
    pref_counts = group["soil_pref"].value_counts().to_dict()
    print(f"\nPlant: {label}  ({len(group)} rows)  soil prefs: {pref_counts}")

    eng = engineer_group(group)
    eng["risk"]       = derive_risk(eng)
    eng["anomaly"]    = derive_anomaly(eng["temp_now"], eng["humidity_now"], eng["light_now"])
    eng["recovering"] = derive_recovering(eng["moisture_delta"], eng["moisture_slope"])

    print(f"  Risk distribution : {eng['risk'].value_counts().sort_index().to_dict()}")
    result_frames.append(eng)

result = pd.concat(result_frames, ignore_index=True)

# ── 7. Shape output to exactly match features_for_edge_impulse.csv columns ───

result["timestamp_iso"]  = result["ts"].dt.strftime("%Y-%m-%d %H:%M:%S")
result["timestamp_unix"] = result["unix"]

EDGE_COLS = [
    "timestamp_iso", "timestamp_unix",
    "soil_now", "moisture_mean", "moisture_delta", "moisture_slope",
    "soil_x_slope", "dry_duration", "temp_now", "humidity_now", "light_now",
    "hour_sin", "hour_cos", "dow_sin", "dow_cos",
    "risk", "anomaly", "recovering",
]

new_rows = result[EDGE_COLS]

# ── 8. Append to existing features_for_edge_impulse.csv ──────────────────────

if EDGE_FILE.exists():
    existing = pd.read_csv(EDGE_FILE)
    existing_timestamps = set(existing["timestamp_unix"].values)
    new_unique = new_rows[~new_rows["timestamp_unix"].isin(existing_timestamps)]
    print(f"\nExisting rows   : {len(existing)}")
    print(f"New unique rows : {len(new_unique)}")
    combined = pd.concat([existing, new_unique], ignore_index=True)
else:
    combined = new_rows
    print(f"\nNo existing file found — creating fresh.")

combined.to_csv(EDGE_FILE, index=False)
print(f"\nSaved {len(combined)} total rows → {EDGE_FILE}")
print(f"\nFinal risk distribution:")
print(combined["risk"].value_counts(normalize=True).sort_index().round(3))
