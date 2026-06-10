"""Train classifier + regression MLP for POF-02 and export to ModelExport.hpp.

Outputs:
  data/model_export.json              — JSON snapshot of all weights
  ../../prototype-non-local/include/ModelExport.hpp  — C++ header (ready to compile)
"""

from pathlib import Path
import json

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, mean_absolute_error
from sklearn.neural_network import MLPClassifier, MLPRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier

ROOT      = Path(__file__).resolve().parent
DATA_FILE = ROOT / "data" / "pof02_synthetic.csv"
OUT_JSON  = ROOT / "data" / "model_export.json"
OUT_HPP   = ROOT / "../../prototype-non-local/include/ModelExport.hpp"

BASE_FEATURES = [
    "soil_now", "moisture_mean", "moisture_delta", "moisture_slope",
    "dry_duration", "temp_now", "humidity_now", "light_now",
]
TIME_FEATURES = ["hour_sin", "hour_cos", "dow_sin", "dow_cos"]
FEATURES      = BASE_FEATURES + TIME_FEATURES + ["soil_x_slope"]

df = pd.read_csv(DATA_FILE)
df["timestamp"] = pd.to_datetime(df["timestamp_iso"], utc=True)
df["soil_x_slope"] = df["soil_now"] * df["moisture_slope"]

df["hour_sin"] = np.sin(2 * np.pi * df["hour_of_day"] / 24.0)
df["hour_cos"] = np.cos(2 * np.pi * df["hour_of_day"] / 24.0)
df["dow_sin"]  = np.sin(2 * np.pi * df["day_of_week"] / 7.0)
df["dow_cos"]  = np.cos(2 * np.pi * df["day_of_week"] / 7.0)

# Chronological split — oldest 80% train, newest 20% test
sorted_df = df.sort_values("timestamp_unix").reset_index(drop=True)
cut       = int(len(sorted_df) * 0.8)
train_df  = sorted_df.iloc[:cut]
test_df   = sorted_df.iloc[cut:]

X_train, X_test = train_df[FEATURES], test_df[FEATURES]
y_cls_train, y_cls_test = train_df["risk"], test_df["risk"]

scaler          = StandardScaler()
X_train_scaled  = scaler.fit_transform(X_train)
X_test_scaled   = scaler.transform(X_test)

# ── Classifier ────────────────────────────────────────────────────────────────
# Partially oversample minority classes so the model sees enough high-stress
# examples without crying wolf on healthy plants.
# Target: each class gets at least 15% of the majority class count.
_cls_counts  = y_cls_train.value_counts()
_target      = int(_cls_counts.max() * 0.15)
_over_frames = [train_df]
for _cls, _count in _cls_counts.items():
    if _count < _target:
        _over_frames.append(train_df[y_cls_train == _cls].sample(
            n=_target - _count, replace=True, random_state=42))
_train_balanced = pd.concat(_over_frames).sample(frac=1, random_state=42)
X_train_bal = scaler.transform(_train_balanced[FEATURES])
y_train_bal  = _train_balanced["risk"]

print("Training classifier MLP...")
mlp_cls = MLPClassifier(hidden_layer_sizes=(12,), random_state=7, max_iter=600)
mlp_cls.fit(X_train_bal, y_train_bal)
print("=== Classifier MLP ===")
print(classification_report(y_cls_test, mlp_cls.predict(X_test_scaled), digits=3))

# ── Regression MLP ────────────────────────────────────────────────────────────
# Only train on rows where plant isn't already at the threshold
# Target: log1p(minutes_until_water) — handles the wide range gracefully
reg_mask_train = train_df["soil_now"] > 33.0
reg_mask_test  = test_df["soil_now"]  > 33.0

y_reg_train = np.log1p(train_df.loc[reg_mask_train, "minutes_until_water"])
y_reg_test  = np.log1p(test_df.loc[reg_mask_test,   "minutes_until_water"])

X_reg_train = X_train_scaled[reg_mask_train]
X_reg_test  = X_test_scaled[reg_mask_test]

print("Training regression MLP...")
mlp_reg = MLPRegressor(
    hidden_layer_sizes=(8,),   # intentionally small — flash is limited on ESP32
    activation="relu",
    random_state=7,
    max_iter=1000,
    early_stopping=True,
    validation_fraction=0.1,
)
mlp_reg.fit(X_reg_train, y_reg_train)

y_pred_log = mlp_reg.predict(X_reg_test)
mae_log    = mean_absolute_error(y_reg_test, y_pred_log)
# Convert back to minutes for a human-readable error
mae_min    = mean_absolute_error(np.expm1(y_reg_test), np.expm1(y_pred_log))
print(f"=== Regression MLP ===")
print(f"  MAE (log scale):   {mae_log:.4f}")
print(f"  MAE (minutes):     {mae_min:.1f} min  ({mae_min/60:.1f} h)")

# ── JSON snapshot ─────────────────────────────────────────────────────────────
export = {
    "feature_order":      FEATURES,
    "base_feature_order": BASE_FEATURES,
    "time_feature_order": TIME_FEATURES,
    "scaler": {
        "mean": scaler.mean_.tolist(),
        "std":  scaler.scale_.tolist(),
    },
    "time_split": {
        "train_end_timestamp_unix":  int(train_df["timestamp_unix"].iloc[-1]),
        "test_start_timestamp_unix": int(test_df["timestamp_unix"].iloc[0]),
    },
    "mlp_classifier": {
        "coefs":      [c.tolist() for c in mlp_cls.coefs_],
        "intercepts": [b.tolist() for b in mlp_cls.intercepts_],
        "classes":    mlp_cls.classes_.tolist(),
    },
    "mlp_regression": {
        "coefs":      [c.tolist() for c in mlp_reg.coefs_],
        "intercepts": [b.tolist() for b in mlp_reg.intercepts_],
    },
}
OUT_JSON.write_text(json.dumps(export, indent=2), encoding="utf-8")
print(f"\nSaved model JSON -> {OUT_JSON}")

# ── Write ModelExport.hpp ─────────────────────────────────────────────────────

def fmt(values, indent=4) -> str:
    pad = " " * indent
    return ", ".join(f"{v:.8f}f" for v in values)

def fmt_matrix_rows(matrix) -> str:
    """matrix shape: [in, out] — each row is one input neuron's weights."""
    lines = []
    for row in matrix:
        lines.append(f"    std::array<float, {len(row)}>{{{fmt(row)}}}")
    return ",\n".join(lines)


# Classifier weights
cls_W1 = mlp_cls.coefs_[0]     # shape [12, 12]
cls_B1 = mlp_cls.intercepts_[0]
cls_W2 = mlp_cls.coefs_[1]     # shape [12, 3]
cls_B2 = mlp_cls.intercepts_[1]

# Regression weights
reg_W1 = mlp_reg.coefs_[0]     # shape [12, 8]
reg_B1 = mlp_reg.intercepts_[0]
reg_W2 = mlp_reg.coefs_[1].flatten()  # shape [8] (output is 1 neuron)
reg_B2 = float(mlp_reg.intercepts_[1][0])

n_feat     = len(FEATURES)
n_cls_hid  = cls_W1.shape[1]
n_cls_out  = cls_W2.shape[1]
n_reg_hid  = reg_W1.shape[1]

hpp = f"""\
#pragma once

// Auto-generated by train_models.py — do not edit by hand.
// Re-run train_models.py to regenerate after retraining.

#include <array>
#include <cstddef>

namespace pof02::modelexport {{

// ── Shared scaler (used by both models) ───────────────────────────────────────

static constexpr std::size_t kFeatureCount = {n_feat};

static constexpr std::array<float, kFeatureCount> kScalerMean = {{{fmt(scaler.mean_)}}};
static constexpr std::array<float, kFeatureCount> kScalerStd  = {{{fmt(scaler.scale_)}}};

// ── Classifier MLP  ({n_feat} → {n_cls_hid} → {n_cls_out} classes) ──────────────────────────

static constexpr std::size_t kHiddenCount = {n_cls_hid};
static constexpr std::size_t kClassCount  = {n_cls_out};

static constexpr std::array<std::array<float, kHiddenCount>, kFeatureCount> kW1 = {{
{fmt_matrix_rows(cls_W1)},
}};
static constexpr std::array<float, kHiddenCount> kB1 = {{{fmt(cls_B1)}}};

static constexpr std::array<std::array<float, kClassCount>, kHiddenCount> kW2 = {{
{fmt_matrix_rows(cls_W2)},
}};
static constexpr std::array<float, kClassCount> kB2      = {{{fmt(cls_B2)}}};
static constexpr std::array<int,   kClassCount> kClasses = {{{', '.join(str(c) for c in mlp_cls.classes_)}}};

// ── Regression MLP  ({n_feat} → {n_reg_hid} → 1, predicts log1p(minutes)) ───────────────

static constexpr std::size_t kRegHiddenCount = {n_reg_hid};

static constexpr std::array<std::array<float, kRegHiddenCount>, kFeatureCount> kRegW1 = {{
{fmt_matrix_rows(reg_W1)},
}};
static constexpr std::array<float, kRegHiddenCount> kRegB1 = {{{fmt(reg_B1)}}};
static constexpr std::array<float, kRegHiddenCount> kRegW2 = {{{fmt(reg_W2)}}};
static constexpr float                              kRegB2 = {reg_B2:.8f}f;

}} // namespace pof02::modelexport
"""

OUT_HPP.resolve().parent.mkdir(parents=True, exist_ok=True)
OUT_HPP.write_text(hpp, encoding="utf-8")
print(f"Wrote ModelExport.hpp -> {OUT_HPP.resolve()}")
