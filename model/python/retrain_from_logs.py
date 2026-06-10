"""retrain_from_logs.py

Retrains the on-device classifier + regression MLPs using real PeaceLily
readings from model/logs/0626_logs, blended with the synthetic dataset.

Fixes the "prediction collapses right after watering" bug: the synthetic set
has almost no rows with a watering-sized moisture_delta (a real watering is
+24% — a z-score of ~16 under the old scaler), so the regressor was
extrapolating garbage in that region.  This script:

  1. Labels real rows with minutes-until-watering from the actual watering
     event (large soil spike) and threshold crossings; right-censored rows
     get a label extrapolated from the plant's measured drying rate.
  2. Adds physics-based post-watering augmentation (high soil, large positive
     delta) labelled with the drying-rate extrapolation, so "just watered"
     maps to a long horizon instead of noise.
  3. Derives risk labels for real rows with the same graded stress score used
     in convert_old_logs.py.
  4. Retrains both MLPs at the existing sizes (13->12->3, 13->8->1) so flash
     usage is unchanged, and writes firmware/include/ModelExport.hpp.

Outputs:
  model/data/model_export.json          — JSON snapshot of new weights
  model/data/peacelily_training_set.csv — labelled real rows (for inspection)
  firmware/include/ModelExport.hpp      — header ready to compile
"""

from datetime import date
from pathlib import Path
import json

import numpy as np
import pandas as pd
from sklearn.metrics import classification_report, mean_absolute_error
from sklearn.neural_network import MLPClassifier, MLPRegressor
from sklearn.preprocessing import StandardScaler

ROOT       = Path(__file__).resolve().parent.parent          # model/
REPO       = ROOT.parent
LOG_FILE   = ROOT / "logs" / "0626_logs" / "plant_readings_rows.csv"
OLD_LOGS   = ROOT / "logs" / "old_logs"
SYNTH_FILE = ROOT / "data" / "pof02_synthetic.csv"
OUT_JSON   = ROOT / "data" / "model_export.json"
OUT_REAL   = ROOT / "data" / "peacelily_training_set.csv"
OUT_HPP    = REPO / "firmware" / "include" / "ModelExport.hpp"

WATER_THRESHOLD = 33.0      # profile.soilMoistureThresholds.midMin (pMid default)
DRY_THRESHOLD   = 35.0      # FeatureEngineering.cpp hardcodes 35.0
WATERING_SPIKE  = 8.0       # real waterings are +24..+52%; sensor noise stays below ~7%
HISTORY_WINDOW  = 56        # kHistorySize in main.cpp — slope/mean span the full buffer
MAX_LABEL_MIN   = 15 * 24 * 60   # matches firmware clamp and synthetic label cap
REAL_WEIGHT     = 4         # repeat real rows so they matter against 24k synthetic
RNG             = np.random.default_rng(42)

# Reported to the cloud (devices.model_version + plant_readings.model_version)
# so the dev dashboard can compare model generations. Bump the prefix on
# methodology changes; the date stamps the training run.
MODEL_VERSION   = f"v2-{date.today():%Y%m%d}"

FEATURES = [
    "soil_now", "moisture_mean", "moisture_delta", "moisture_slope",
    "dry_duration", "temp_now", "humidity_now", "light_now",
    "hour_sin", "hour_cos", "dow_sin", "dow_cos",
    "soil_x_slope",
]

# pMid soil band, mirrors PlantTypes.hpp defaults: (lowMax, midMin, midMax, highMin, highMax)
BAND_MIN, BAND_MAX = 33.0, 55.0


# ── Feature engineering (mirrors FeatureEngineering.cpp) ─────────────────────

def engineer(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy().sort_values("ts").reset_index(drop=True)
    soil = df["soil_now"].values
    unix = df["unix"].values
    n = len(df)

    mean_  = np.zeros(n)
    delta  = np.zeros(n)
    slope  = np.zeros(n)
    dry_h  = np.zeros(n)
    streak = 0

    for i in range(n):
        w = soil[max(0, i - HISTORY_WINDOW + 1): i + 1]
        mean_[i] = w.mean()
        delta[i] = soil[i] - soil[i - 1] if i > 0 else 0.0
        if len(w) >= 2:
            slope[i] = (w[-1] - w[0]) / (len(w) - 1)
        streak = streak + 1 if soil[i] < DRY_THRESHOLD else 0
        if streak >= 2:
            dry_h[i] = (unix[i] - unix[i - streak + 1]) / 3600.0

    df["moisture_mean"]  = mean_
    df["moisture_delta"] = delta
    df["moisture_slope"] = slope
    df["dry_duration"]   = dry_h
    df["soil_x_slope"]   = soil * slope

    hour, dow = df["ts"].dt.hour, df["ts"].dt.dayofweek
    df["hour_sin"] = np.sin(2 * np.pi * hour / 24.0)
    df["hour_cos"] = np.cos(2 * np.pi * hour / 24.0)
    df["dow_sin"]  = np.sin(2 * np.pi * dow / 7.0)
    df["dow_cos"]  = np.cos(2 * np.pi * dow / 7.0)
    return df


# ── Drying rate (% per minute) measured after the last watering ──────────────

def measure_drying_rate(df: pd.DataFrame) -> float:
    """Linear fit over the longest post-watering drainage segment."""
    watered = df["moisture_delta"] >= WATERING_SPIKE
    start = int(np.where(watered)[0][-1]) if watered.any() else 0
    seg = df.iloc[start:]
    if len(seg) < 4:
        return 0.0021  # fallback ≈ 3%/day
    t_min = (seg["unix"] - seg["unix"].iloc[0]) / 60.0
    rate = -np.polyfit(t_min, seg["soil_now"], 1)[0]
    return max(rate, 1e-4)


# ── Regression labels ─────────────────────────────────────────────────────────

def label_minutes(df: pd.DataFrame, drying_rate: float) -> np.ndarray:
    soil = df["soil_now"].values
    unix = df["unix"].values
    watered = (df["moisture_delta"] >= WATERING_SPIKE).values
    n = len(df)
    labels = np.zeros(n)

    for i in range(n):
        if soil[i] <= WATER_THRESHOLD:
            labels[i] = 0.0
            continue
        lab = None
        for j in range(i + 1, n):
            if soil[j] <= WATER_THRESHOLD or watered[j]:
                lab = (unix[j] - unix[i]) / 60.0
                break
        if lab is None:  # right-censored: extrapolate at measured drying rate
            lab = (soil[i] - WATER_THRESHOLD) / drying_rate
        labels[i] = min(lab, MAX_LABEL_MIN)
    return labels


# ── Risk labels (graded stress score, same as convert_old_logs.py) ───────────

def _c01(x):
    return np.clip(x, 0.0, 1.0)

def derive_risk(df: pd.DataFrame) -> np.ndarray:
    band_range = BAND_MAX - BAND_MIN
    low_soil  = _c01((BAND_MIN + band_range * 0.3 - df["soil_now"]) / (band_range * 0.3))
    drying    = _c01(-df["moisture_slope"] / 4.0)
    dry_acc   = _c01(df["dry_duration"] / 3.0)
    temp_f    = _c01((df["temp_now"] - 20) / 15)
    hum_f     = _c01((60 - df["humidity_now"]) / 40)
    light_f   = _c01((df["light_now"] - 200) / 700)
    evap      = 0.45 * temp_f + 0.30 * hum_f + 0.25 * light_f
    stress = (0.22 * low_soil + 0.18 * drying + 0.16 * dry_acc + 0.14 * evap
              + 0.14 * low_soil * drying + 0.10 * evap * dry_acc
              + 0.06 * low_soil * evap)
    return np.select([stress > 0.62, stress > 0.34], [2, 1], default=0)


# ── Post-watering augmentation ────────────────────────────────────────────────

def augment_post_watering(real: pd.DataFrame, drying_rate: float, n: int = 400) -> pd.DataFrame:
    """Synthesises 'just watered' rows so a watering spike maps to a long
    horizon. Environment values are bootstrapped from real readings; the label
    follows the measured drying rate with ±30% jitter."""
    base = real.sample(n=n, replace=True, random_state=42).reset_index(drop=True)
    soil_prev = RNG.uniform(33.0, 46.0, n)            # user waters around 36–46%
    spike     = RNG.uniform(WATERING_SPIKE, 30.0, n)
    soil_now  = np.minimum(soil_prev + spike, 85.0)

    out = pd.DataFrame({
        "soil_now":       soil_now,
        # 56-sample window: mean barely moves, slope = spike spread over buffer
        "moisture_mean":  soil_prev + spike / HISTORY_WINDOW,
        "moisture_delta": soil_now - soil_prev,
        "moisture_slope": spike / (HISTORY_WINDOW - 1) + RNG.normal(0, 0.05, n),
        "dry_duration":   0.0,
        "temp_now":       base["temp_now"].values + RNG.normal(0, 0.5, n),
        "humidity_now":   base["humidity_now"].values + RNG.normal(0, 2.0, n),
        "light_now":      base["light_now"].values,
        "hour_sin":       base["hour_sin"].values,
        "hour_cos":       base["hour_cos"].values,
        "dow_sin":        base["dow_sin"].values,
        "dow_cos":        base["dow_cos"].values,
    })
    out["soil_x_slope"] = out["soil_now"] * out["moisture_slope"]
    rate = drying_rate * RNG.uniform(0.7, 1.3, n)
    out["minutes_until_water"] = np.minimum((soil_now - WATER_THRESHOLD) / rate, MAX_LABEL_MIN)
    out["risk"] = derive_risk(out)
    return out


# ── Header export ─────────────────────────────────────────────────────────────

def write_hpp(scaler, mlp_cls, mlp_reg, path: Path) -> None:
    def fmt(v):
        return ", ".join(f"{x:.8f}f" for x in v)

    def rows(m):
        return ",\n".join(f"    std::array<float, {len(r)}>{{{fmt(r)}}}" for r in m)

    cW1, cB1, cW2, cB2 = mlp_cls.coefs_[0], mlp_cls.intercepts_[0], mlp_cls.coefs_[1], mlp_cls.intercepts_[1]
    rW1, rB1 = mlp_reg.coefs_[0], mlp_reg.intercepts_[0]
    rW2, rB2 = mlp_reg.coefs_[1].flatten(), float(mlp_reg.intercepts_[1][0])

    path.write_text(f"""\
#pragma once

// Auto-generated by retrain_from_logs.py — do not edit by hand.
// Trained on synthetic data + real PeaceLily readings (0626_logs).

#include <array>
#include <cstddef>

namespace modelexport {{

// Reported to the cloud so readings can be attributed to a model generation.
static constexpr const char *kModelVersion = "{MODEL_VERSION}";

// ── Shared scaler (used by both models) ───────────────────────────────────────

static constexpr std::size_t kFeatureCount = {len(FEATURES)};

static constexpr std::array<float, kFeatureCount> kScalerMean = {{{fmt(scaler.mean_)}}};
static constexpr std::array<float, kFeatureCount> kScalerStd  = {{{fmt(scaler.scale_)}}};

// ── Classifier MLP  ({len(FEATURES)} → {cW1.shape[1]} → {cW2.shape[1]} classes) ──────────────────────────

static constexpr std::size_t kHiddenCount = {cW1.shape[1]};
static constexpr std::size_t kClassCount  = {cW2.shape[1]};

static constexpr std::array<std::array<float, kHiddenCount>, kFeatureCount> kW1 = {{
{rows(cW1)},
}};
static constexpr std::array<float, kHiddenCount> kB1 = {{{fmt(cB1)}}};

static constexpr std::array<std::array<float, kClassCount>, kHiddenCount> kW2 = {{
{rows(cW2)},
}};
static constexpr std::array<float, kClassCount> kB2      = {{{fmt(cB2)}}};
static constexpr std::array<int,   kClassCount> kClasses = {{{", ".join(str(c) for c in mlp_cls.classes_)}}};

// ── Regression MLP  ({len(FEATURES)} → {rW1.shape[1]} → 1, predicts log1p(minutes)) ───────────────

static constexpr std::size_t kRegHiddenCount = {rW1.shape[1]};

static constexpr std::array<std::array<float, kRegHiddenCount>, kFeatureCount> kRegW1 = {{
{rows(rW1)},
}};
static constexpr std::array<float, kRegHiddenCount> kRegB1 = {{{fmt(rB1)}}};
static constexpr std::array<float, kRegHiddenCount> kRegW2 = {{{fmt(rW2)}}};
static constexpr float                              kRegB2 = {rB2:.8f}f;

}} // namespace modelexport
""", encoding="utf-8")
    print(f"Wrote {path}")


# ── Inference helpers (numpy mirror of the firmware) ─────────────────────────

def predict_minutes(x, scaler, mlp_reg):
    xs = (np.asarray(x) - scaler.mean_) / scaler.scale_
    h = np.maximum(0.0, xs @ mlp_reg.coefs_[0] + mlp_reg.intercepts_[0])
    log_min = float(h @ mlp_reg.coefs_[1].flatten() + mlp_reg.intercepts_[1][0])
    return float(np.clip(np.expm1(max(0.0, log_min)), 0, MAX_LABEL_MIN))


# ── Main ──────────────────────────────────────────────────────────────────────

RENAME = {
    "soil_moisture_pct": "soil_now", "temperature_c": "temp_now",
    "humidity_pct": "humidity_now", "light_level_pct": "light_now",
}


def load_real_sources() -> list[pd.DataFrame]:
    """PeaceLily from 0626_logs + Aglaonema from old_logs.

    Aglaonema is excluded from 0626_logs because that device has a hardware
    fault affecting the light and soil moisture sensors in that period."""
    new = pd.read_csv(LOG_FILE)
    new = new[new["plant_label"] == "PeaceLily"].rename(columns=RENAME)
    new["ts"] = pd.to_datetime(new["timestamp"], utc=True, format="mixed")

    frames = [pd.read_csv(p) for p in sorted(OLD_LOGS.glob("*.csv"))]
    old = pd.concat(frames, ignore_index=True)
    old = old[old["plant_label"] == "Aglaonema"].rename(columns=RENAME)
    old["ts"] = pd.to_datetime(old["timestamp_utc"], utc=True, format="mixed")

    plants = []
    for df in (new, old):
        # robust across pandas versions (3.0 stores datetime64[us], not [ns])
        df["unix"] = df["ts"].map(pd.Timestamp.timestamp).astype(np.int64)
        # drop sensor glitches (rail readings)
        df = df[(df["soil_now"] > 1.0) & (df["soil_now"] < 99.0)]
        plants.append(df.sort_values("unix").reset_index(drop=True))
    return plants


def main():
    real_frames, aug_frames = [], []
    for raw in load_real_sources():
        plant = raw["plant_label"].iloc[0]
        eng = engineer(raw)
        rate = measure_drying_rate(eng)
        print(f"{plant}: {len(eng)} rows, drying rate {rate*1440:.2f} %/day, "
              f"watering events: {int((eng['moisture_delta'] >= WATERING_SPIKE).sum())}")
        eng["minutes_until_water"] = label_minutes(eng, rate)
        eng["risk"] = derive_risk(eng)
        print(f"  risk distribution: {eng['risk'].value_counts().sort_index().to_dict()}")
        real_frames.append(eng)
        aug_frames.append(augment_post_watering(eng, rate, n=200))

    real = pd.concat(real_frames, ignore_index=True)
    real[["plant_label"] + FEATURES + ["minutes_until_water", "risk"]].to_csv(OUT_REAL, index=False)
    aug = pd.concat(aug_frames, ignore_index=True)

    synth = pd.read_csv(SYNTH_FILE)
    if "hour_sin" not in synth.columns:
        synth["hour_sin"] = np.sin(2 * np.pi * synth["hour_of_day"] / 24.0)
        synth["hour_cos"] = np.cos(2 * np.pi * synth["hour_of_day"] / 24.0)
        synth["dow_sin"]  = np.sin(2 * np.pi * synth["day_of_week"] / 7.0)
        synth["dow_cos"]  = np.cos(2 * np.pi * synth["day_of_week"] / 7.0)

    cols = FEATURES + ["minutes_until_water", "risk"]
    # Hold out the newest 20% of each plant's rows as a chronological test set
    tr, te = [], []
    for f in real_frames:
        cut = int(len(f) * 0.8)
        tr.append(f.iloc[:cut])
        te.append(f.iloc[cut:])
    real_train = pd.concat(tr, ignore_index=True)
    real_test  = pd.concat(te, ignore_index=True)

    train = pd.concat(
        [synth[cols]] + [real_train[cols]] * REAL_WEIGHT + [aug[cols]],
        ignore_index=True).dropna()
    print(f"Training set: {len(synth)} synthetic + {len(real_train)}x{REAL_WEIGHT} real "
          f"+ {len(aug)} augmented = {len(train)}")

    X = train[FEATURES].values
    scaler = StandardScaler().fit(X)
    Xs = scaler.transform(X)

    # Classifier — rebalance scarce high-stress class as in train_models.py
    y_cls = train["risk"].astype(int).values
    counts = pd.Series(y_cls).value_counts()
    target = int(counts.max() * 0.15)
    idx = [np.arange(len(y_cls))]
    for cls, cnt in counts.items():
        if cnt < target:
            idx.append(RNG.choice(np.where(y_cls == cls)[0], target - cnt))
    bal = np.concatenate(idx)
    RNG.shuffle(bal)

    print("\nTraining classifier MLP...")
    mlp_cls = MLPClassifier(hidden_layer_sizes=(12,), random_state=7, max_iter=800)
    mlp_cls.fit(Xs[bal], y_cls[bal])
    Xt = scaler.transform(real_test[FEATURES].values)
    print("=== Classifier on held-out real rows ===")
    print(classification_report(real_test["risk"], mlp_cls.predict(Xt),
                                digits=3, zero_division=0))

    # Regression — only rows above watering threshold, log1p target
    mask = X[:, 0] > WATER_THRESHOLD
    print("Training regression MLP...")
    mlp_reg = MLPRegressor(hidden_layer_sizes=(8,), activation="relu", random_state=7,
                           max_iter=1500, early_stopping=True, validation_fraction=0.1)
    mlp_reg.fit(Xs[mask], np.log1p(train["minutes_until_water"].values[mask]))

    tmask = real_test["soil_now"].values > WATER_THRESHOLD
    if tmask.any():
        pred = [predict_minutes(x, scaler, mlp_reg) for x in real_test[FEATURES].values[tmask]]
        mae = mean_absolute_error(real_test["minutes_until_water"].values[tmask], pred)
        print(f"=== Regression on held-out real rows: MAE {mae:.0f} min ({mae/60:.1f} h) ===")

    # Sanity check: the real watering moment (2026-06-05, +24.6% spike)
    spike_rows = real[real["moisture_delta"] >= WATERING_SPIKE]
    for _, r in spike_rows.iterrows():
        m = predict_minutes(r[FEATURES].values.astype(float), scaler, mlp_reg)
        print(f"Sanity — just-watered row (soil {r['soil_now']:.1f}, "
              f"delta +{r['moisture_delta']:.1f}): predicted {m/1440:.1f} days "
              f"(label {r['minutes_until_water']/1440:.1f} days)")

    OUT_JSON.write_text(json.dumps({
        "feature_order": FEATURES,
        "scaler": {"mean": scaler.mean_.tolist(), "std": scaler.scale_.tolist()},
        "mlp_classifier": {
            "coefs": [c.tolist() for c in mlp_cls.coefs_],
            "intercepts": [b.tolist() for b in mlp_cls.intercepts_],
            "classes": mlp_cls.classes_.tolist(),
        },
        "mlp_regression": {
            "coefs": [c.tolist() for c in mlp_reg.coefs_],
            "intercepts": [b.tolist() for b in mlp_reg.intercepts_],
        },
    }, indent=2), encoding="utf-8")
    print(f"Saved model JSON -> {OUT_JSON}")

    write_hpp(scaler, mlp_cls, mlp_reg, OUT_HPP)


if __name__ == "__main__":
    main()
