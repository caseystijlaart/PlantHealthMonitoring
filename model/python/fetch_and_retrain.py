"""fetch_and_retrain.py

Fetches real plant readings from Supabase, derives training labels from
actual soil moisture trajectories (watering events detected as soil spikes),
merges with the synthetic dataset, retrains both MLP models, and writes
a new ModelExport.hpp ready to flash.

Usage
-----
    python fetch_and_retrain.py

Edit the CONFIG section below if your project URL or table name differs.
API_KEY is read from the environment variable SUPABASE_API_KEY, or falls
back to the value in secrets.ini so you never hard-code it here.
"""

from __future__ import annotations

import math
import os
import sys
from configparser import ConfigParser
from pathlib import Path

import numpy as np
import pandas as pd
import requests
from sklearn.metrics import classification_report, mean_absolute_error
from sklearn.neural_network import MLPClassifier, MLPRegressor
from sklearn.preprocessing import StandardScaler

# ── CONFIG ────────────────────────────────────────────────────────────────────

SUPABASE_URL   = "https://yjjpgvsycxlaqubvedoa.supabase.co"
TABLE          = "plant_readings"
PAGE_SIZE      = 1000          # Supabase default page limit

WATER_THRESHOLD     = 33.0     # soil % — must match PlantRuleProfile midMin
WATERING_SPIKE      = 8.0      # minimum soil % increase to count as a watering event
DRY_THRESHOLD       = 35.0     # soil % below which "dry_duration" accumulates
HISTORY_WINDOW      = 8        # samples used for rolling feature computation
MAX_LABEL_MINUTES   = 7 * 24 * 60  # cap for look-ahead labels (7 days)

ROOT        = Path(__file__).resolve().parent
SYNTH_FILE  = ROOT / "data" / "pof02_synthetic.csv"
REAL_FILE   = ROOT / "data" / "real_readings.csv"
OUT_HPP     = ROOT / "../../prototype-non-local/include/ModelExport.hpp"

FEATURES = [
    "soil_now", "moisture_mean", "moisture_delta", "moisture_slope",
    "dry_duration", "temp_now", "humidity_now", "light_now",
    "hour_sin", "hour_cos", "dow_sin", "dow_cos",
    "soil_x_slope",
]

# ── Resolve API key ───────────────────────────────────────────────────────────

def get_api_key() -> str:
    # 1. Environment variable (preferred for CI / automated runs)
    key = os.environ.get("SUPABASE_API_KEY", "")
    if key:
        return key

    # 2. Fall back to secrets.ini next to this file (or two levels up)
    for candidate in [ROOT / "secrets.ini",
                      ROOT / "../../prototype-non-local/secrets.ini"]:
        if candidate.exists():
            cfg = ConfigParser()
            cfg.read(candidate)
            for section in cfg.sections():
                for value in cfg[section].values():
                    # secrets.ini lines look like: -D API_KEY=\"...\"; extract the value
                    if "API_KEY" in value:
                        import re
                        m = re.search(r'API_KEY\s*=\s*[\\"]*([\w\-\.]+)', value)
                        if m:
                            return m.group(1)

    sys.exit(
        "ERROR: SUPABASE_API_KEY not found.\n"
        "  Set it as an environment variable:  export SUPABASE_API_KEY=your_key\n"
        "  or ensure secrets.ini is present."
    )

# ── Fetch from Supabase ───────────────────────────────────────────────────────

def fetch_all_readings(api_key: str) -> pd.DataFrame:
    headers = {
        "apikey": api_key,
        "Authorization": f"Bearer {api_key}",
    }

    frames: list[pd.DataFrame] = []
    offset = 0

    print("Fetching readings from Supabase...")
    while True:
        url = (
            f"{SUPABASE_URL}/rest/v1/{TABLE}"
            f"?select=plant_label,soil_moisture_pct,temperature_c,"
            f"humidity_pct,light_level_pct,created_at"
            f"&order=created_at.asc"
            f"&offset={offset}&limit={PAGE_SIZE}"
        )
        resp = requests.get(url, headers=headers, timeout=30)
        resp.raise_for_status()

        batch = resp.json()
        if not batch:
            break

        frames.append(pd.DataFrame(batch))
        print(f"  fetched rows {offset}–{offset + len(batch) - 1}")
        offset += len(batch)

        if len(batch) < PAGE_SIZE:
            break

    if not frames:
        sys.exit("No data returned from Supabase.")

    df = pd.concat(frames, ignore_index=True)
    print(f"Total rows fetched: {len(df)}")
    return df


# ── Feature engineering (mirrors FeatureEngineering.cpp) ─────────────────────

def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Compute rolling features from sorted sensor readings.
    Matches the logic in FeatureEngineering::Build() on the ESP32.
    """
    df = df.copy().sort_values("created_at").reset_index(drop=True)

    # Parse timestamp
    df["ts"] = pd.to_datetime(df["created_at"], utc=True)
    df["hour_of_day"] = df["ts"].dt.hour
    df["day_of_week"]  = df["ts"].dt.dayofweek
    df["unix"]         = df["ts"].astype(np.int64) // 10**9

    soil = df["soil_moisture_pct"].values
    n    = len(soil)

    moisture_mean   = np.zeros(n)
    moisture_delta  = np.zeros(n)
    moisture_slope  = np.zeros(n)
    dry_duration    = np.zeros(n)

    dry_streak = 0   # consecutive samples below DRY_THRESHOLD

    for i in range(n):
        win_start = max(0, i - HISTORY_WINDOW + 1)
        window    = soil[win_start : i + 1]

        moisture_mean[i]  = window.mean()
        moisture_delta[i] = soil[i] - soil[i - 1] if i > 0 else 0.0
        if len(window) >= 2:
            moisture_slope[i] = (window[-1] - window[0]) / (len(window) - 1)

        # Dry duration: consecutive readings below threshold up to now
        if soil[i] < DRY_THRESHOLD:
            dry_streak += 1
        else:
            dry_streak = 0

        if dry_streak >= 2:
            # Time from oldest dry sample to current
            oldest_dry_idx = i - dry_streak + 1
            elapsed_sec    = df["unix"].iloc[i] - df["unix"].iloc[oldest_dry_idx]
            dry_duration[i] = elapsed_sec / 3600.0

    df["moisture_mean"]  = moisture_mean
    df["moisture_delta"] = moisture_delta
    df["moisture_slope"] = moisture_slope
    df["dry_duration"]   = dry_duration

    df["hour_sin"] = np.sin(2 * np.pi * df["hour_of_day"] / 24.0)
    df["hour_cos"] = np.cos(2 * np.pi * df["hour_of_day"] / 24.0)
    df["dow_sin"]  = np.sin(2 * np.pi * df["day_of_week"] / 7.0)
    df["dow_cos"]  = np.cos(2 * np.pi * df["day_of_week"] / 7.0)

    df = df.rename(columns={
        "soil_moisture_pct": "soil_now",
        "temperature_c":     "temp_now",
        "humidity_pct":      "humidity_now",
        "light_level_pct":   "light_now",
    })

    return df


# ── Detect watering events ────────────────────────────────────────────────────

def detect_watering_events(df: pd.DataFrame) -> pd.Series:
    """
    Returns a boolean Series — True where a watering event occurred.
    Detected as a soil moisture increase of >= WATERING_SPIKE % between readings.
    """
    delta = df["soil_now"].diff()
    return delta >= WATERING_SPIKE


# ── Compute minutes_until_water labels ───────────────────────────────────────

def compute_labels(df: pd.DataFrame, watered: pd.Series) -> pd.DataFrame:
    """
    For each row, look ahead to find the earliest of:
      a) soil dropping to/below WATER_THRESHOLD, or
      b) a watering event (user watered before threshold was reached)

    The unix timestamps give real elapsed minutes between readings.
    Rows where soil is already at/below threshold get label 0.
    Rows where nothing is found within MAX_LABEL_MINUTES are capped.
    """
    soil      = df["soil_now"].values
    unix      = df["unix"].values
    watered_v = watered.values
    n         = len(df)

    labels = np.full(n, float(MAX_LABEL_MINUTES))

    for i in range(n):
        if soil[i] <= WATER_THRESHOLD:
            labels[i] = 0.0
            continue

        for j in range(i + 1, n):
            elapsed_min = (unix[j] - unix[i]) / 60.0

            if elapsed_min > MAX_LABEL_MINUTES:
                break  # already beyond cap

            # Threshold crossing
            if soil[j] <= WATER_THRESHOLD:
                labels[i] = elapsed_min
                break

            # User watered before threshold — treat as "needed water at this point"
            if watered_v[j]:
                labels[i] = elapsed_min
                break

    return df.assign(minutes_until_water=labels)


# ── Write ModelExport.hpp ─────────────────────────────────────────────────────

def write_hpp(scaler, mlp_cls, mlp_reg, out_path: Path) -> None:
    def fmt(values) -> str:
        return ", ".join(f"{v:.8f}f" for v in values)

    def fmt_matrix(matrix) -> str:
        lines = []
        for row in matrix:
            lines.append(f"    std::array<float, {len(row)}>{{{fmt(row)}}}")
        return ",\n".join(lines)

    cls_W1 = mlp_cls.coefs_[0]
    cls_B1 = mlp_cls.intercepts_[0]
    cls_W2 = mlp_cls.coefs_[1]
    cls_B2 = mlp_cls.intercepts_[1]

    reg_W1 = mlp_reg.coefs_[0]
    reg_B1 = mlp_reg.intercepts_[0]
    reg_W2 = mlp_reg.coefs_[1].flatten()
    reg_B2 = float(mlp_reg.intercepts_[1][0])

    n_feat    = len(FEATURES)
    n_cls_hid = cls_W1.shape[1]
    n_cls_out = cls_W2.shape[1]
    n_reg_hid = reg_W1.shape[1]

    hpp = f"""\
#pragma once

// Auto-generated by fetch_and_retrain.py — do not edit by hand.
// Re-run fetch_and_retrain.py to update weights from real sensor data.

#include <array>
#include <cstddef>

namespace pof02::modelexport {{

static constexpr std::size_t kFeatureCount = {n_feat};

static constexpr std::array<float, kFeatureCount> kScalerMean = {{{fmt(scaler.mean_)}}};
static constexpr std::array<float, kFeatureCount> kScalerStd  = {{{fmt(scaler.scale_)}}};

// ── Classifier MLP  ({n_feat} → {n_cls_hid} → {n_cls_out} classes) ─────────────────────

static constexpr std::size_t kHiddenCount = {n_cls_hid};
static constexpr std::size_t kClassCount  = {n_cls_out};

static constexpr std::array<std::array<float, kHiddenCount>, kFeatureCount> kW1 = {{
{fmt_matrix(cls_W1)},
}};
static constexpr std::array<float, kHiddenCount> kB1 = {{{fmt(cls_B1)}}};

static constexpr std::array<std::array<float, kClassCount>, kHiddenCount> kW2 = {{
{fmt_matrix(cls_W2)},
}};
static constexpr std::array<float, kClassCount> kB2      = {{{fmt(cls_B2)}}};
static constexpr std::array<int,   kClassCount> kClasses = {{{', '.join(str(c) for c in mlp_cls.classes_)}}};

// ── Regression MLP  ({n_feat} → {n_reg_hid} → 1, predicts log1p(minutes)) ──────────────

static constexpr std::size_t kRegHiddenCount = {n_reg_hid};

static constexpr std::array<std::array<float, kRegHiddenCount>, kFeatureCount> kRegW1 = {{
{fmt_matrix(reg_W1)},
}};
static constexpr std::array<float, kRegHiddenCount> kRegB1 = {{{fmt(reg_B1)}}};
static constexpr std::array<float, kRegHiddenCount> kRegW2 = {{{fmt(reg_W2)}}};
static constexpr float                              kRegB2 = {reg_B2:.8f}f;

}} // namespace pof02::modelexport
"""
    out_path.resolve().parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(hpp, encoding="utf-8")
    print(f"Wrote ModelExport.hpp → {out_path.resolve()}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    api_key = get_api_key()

    # 1. Fetch and process real data
    raw = fetch_all_readings(api_key)
    raw.to_csv(REAL_FILE, index=False)
    print(f"Saved raw fetch → {REAL_FILE}")

    # Process per plant label so features don't bleed across plants
    real_frames: list[pd.DataFrame] = []
    for label, group in raw.groupby("plant_label"):
        print(f"\nProcessing plant: {label}  ({len(group)} rows)")
        eng     = engineer_features(group)
        eng["soil_x_slope"] = eng["soil_now"] * eng["moisture_slope"]
        watered = detect_watering_events(eng)
        labelled = compute_labels(eng, watered)
        real_frames.append(labelled)
        watering_events = int(watered.sum())
        print(f"  Watering events detected: {watering_events}")

    real_df = pd.concat(real_frames, ignore_index=True)
    real_df["source"] = "real"

    # 2. Load synthetic data
    if not SYNTH_FILE.exists():
        print(f"\nSynthetic data not found at {SYNTH_FILE}.")
        print("Run generate_training_data.py first, or train on real data only.")
        combined = real_df
    else:
        synth_df = pd.read_csv(SYNTH_FILE)
        synth_df["source"] = "synthetic"

        # Add time features to synthetic if missing
        if "hour_sin" not in synth_df.columns:
            synth_df["hour_sin"] = np.sin(2 * np.pi * synth_df["hour_of_day"] / 24.0)
            synth_df["hour_cos"] = np.cos(2 * np.pi * synth_df["hour_of_day"] / 24.0)
            synth_df["dow_sin"]  = np.sin(2 * np.pi * synth_df["day_of_week"]  / 7.0)
            synth_df["dow_cos"]  = np.cos(2 * np.pi * synth_df["day_of_week"]  / 7.0)

        # Real data gets 3× weight so the model improves toward reality over time
        real_repeated = pd.concat([real_df] * 3, ignore_index=True)
        combined = pd.concat([synth_df, real_repeated], ignore_index=True)
        print(f"\nCombined dataset: {len(synth_df)} synthetic + "
              f"{len(real_df)} real ({len(real_df)*3} weighted) = {len(combined)} total rows")

    # 3. Build feature matrix
    combined = combined.dropna(subset=FEATURES + ["minutes_until_water", "risk"])
    X = combined[FEATURES].values
    y_cls = combined["risk"].astype(int).values
    y_reg = np.log1p(combined["minutes_until_water"].clip(0, MAX_LABEL_MINUTES).values)

    # Chronological split on real data rows; random split fine for synthetic
    real_mask = combined["source"] == "real"
    if real_mask.sum() > 20:
        real_idx  = combined.index[real_mask].tolist()
        cut       = int(len(real_idx) * 0.8)
        test_idx  = set(real_idx[cut:])
        test_mask = combined.index.isin(test_idx)
    else:
        rng = np.random.default_rng(42)
        test_mask = rng.random(len(combined)) > 0.8

    X_train, X_test   = X[~test_mask],    X[test_mask]
    yc_train, yc_test = y_cls[~test_mask], y_cls[test_mask]
    yr_train, yr_test = y_reg[~test_mask], y_reg[test_mask]

    scaler         = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled  = scaler.transform(X_test)

    # 4. Train classifier
    print("\nTraining classifier MLP...")
    mlp_cls = MLPClassifier(hidden_layer_sizes=(12,), random_state=7, max_iter=600)
    mlp_cls.fit(X_train_scaled, yc_train)
    print("=== Classifier ===")
    print(classification_report(yc_test, mlp_cls.predict(X_test_scaled), digits=3))

    # 5. Train regression (only on rows above threshold)
    above = X_train[:, 0] > WATER_THRESHOLD   # soil_now is feature index 0
    above_test = X_test[:, 0] > WATER_THRESHOLD
    print("Training regression MLP...")
    mlp_reg = MLPRegressor(
        hidden_layer_sizes=(8,),
        activation="relu",
        random_state=7,
        max_iter=1000,
        early_stopping=True,
        validation_fraction=0.1,
    )
    mlp_reg.fit(X_train_scaled[above], yr_train[above])

    y_pred = mlp_reg.predict(X_test_scaled[above_test])
    mae_min = mean_absolute_error(
        np.expm1(yr_test[above_test]),
        np.expm1(y_pred)
    )
    print(f"=== Regression  MAE: {mae_min:.0f} min  ({mae_min/60:.1f} h) ===")

    # 6. Write ModelExport.hpp
    write_hpp(scaler, mlp_cls, mlp_reg, OUT_HPP)
    print("\nDone. Flash the firmware to deploy updated weights.")


if __name__ == "__main__":
    main()
