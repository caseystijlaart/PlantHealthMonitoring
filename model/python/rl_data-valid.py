#!/usr/bin/env python3
"""Run exported model inference on a captured device log and compare logged vs rebuilt predictions."""

from __future__ import annotations

from pathlib import Path
import argparse
import json

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent
DEFAULT_INPUT = ROOT.parent / "data" / "log_2026-04-18.csv"
DEFAULT_MODEL = ROOT / "data" / "model_export.json"
DEFAULT_OUTPUT = ROOT / "data" / "output" / "log_2026-04-18_model_predictions.csv"

IGNORED_CAPTURED_COLUMNS = [
    "risk_class",
    "confidence",
    "prob_healthy",
    "prob_moderate_stress",
    "prob_high_stress",
    "action_water",
    "action_reduce_temp",
    "action_increase_humidity",
    "action_increase_light",
    "recommendation_summary",
]


class ExportedMLPModel:
    """Inference wrapper around exported scaler + MLP weights."""

    def __init__(self, cfg: dict):
        self.feature_order = cfg["feature_order"]
        self.mean = np.array(cfg["scaler"]["mean"], dtype=float)
        self.std = np.array(cfg["scaler"]["std"], dtype=float)
        self.std[self.std == 0] = 1.0

        self.W1 = np.array(cfg["mlp"]["coefs"][0], dtype=float)
        self.W2 = np.array(cfg["mlp"]["coefs"][1], dtype=float)
        self.b1 = np.array(cfg["mlp"]["intercepts"][0], dtype=float)
        self.b2 = np.array(cfg["mlp"]["intercepts"][1], dtype=float)
        self.classes_ = np.array(cfg["mlp"]["classes"], dtype=int)

    @staticmethod
    def _relu(x: np.ndarray) -> np.ndarray:
        return np.maximum(x, 0.0)

    @staticmethod
    def _softmax(x: np.ndarray) -> np.ndarray:
        z = x - np.max(x, axis=1, keepdims=True)
        e = np.exp(z)
        return e / e.sum(axis=1, keepdims=True)

    def predict_proba(self, X: pd.DataFrame) -> np.ndarray:
        Xv = X[self.feature_order].to_numpy(dtype=float)
        Xn = (Xv - self.mean) / self.std
        hidden = self._relu(Xn @ self.W1 + self.b1)
        logits = hidden @ self.W2 + self.b2
        return self._softmax(logits)

    def predict(self, X: pd.DataFrame) -> np.ndarray:
        probs = self.predict_proba(X)
        indices = np.argmax(probs, axis=1)
        return self.classes_[indices]


def clip01(x):
    return np.clip(x, 0.0, 1.0)


def _require_columns(df: pd.DataFrame, required: list[str]) -> None:
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required input columns: {missing}")


def preserve_logged_outputs(df: pd.DataFrame) -> pd.DataFrame:
    """Copy logged prediction/action columns to prefixed columns for later comparison."""
    out = df.copy()
    for col in IGNORED_CAPTURED_COLUMNS:
        if col in out.columns:
            out[f"logged_{col}"] = out[col]
    return out


def engineer_features(raw_df: pd.DataFrame) -> pd.DataFrame:
    """Create training-style features expected by model_export.json from device logs."""
    df = preserve_logged_outputs(raw_df)

    present_ignored = [c for c in IGNORED_CAPTURED_COLUMNS if c in df.columns]
    if present_ignored:
        df = df.drop(columns=present_ignored)

    required = [
        "timestamp_utc",
        "unix_time",
        "soil_moisture_pct",
        "temperature_c",
        "humidity_pct",
        "light_level_pct",
    ]
    _require_columns(df, required)

    if "plant_label" not in df.columns:
        df["plant_label"] = "plant_1"
    if "device_id" not in df.columns:
        if "device_name" in df.columns:
            df["device_id"] = df["device_name"].astype(str)
        else:
            df["device_id"] = "device_1"
    if "device_name" not in df.columns:
        df["device_name"] = df["device_id"].astype(str)

    df["timestamp_utc"] = pd.to_datetime(df["timestamp_utc"], utc=True)

    group_cols = ["plant_label", "device_id"]
    df = df.sort_values(group_cols + ["timestamp_utc"]).reset_index(drop=True)

    df["timestamp_iso"] = df["timestamp_utc"].dt.strftime("%Y-%m-%d %H:%M:%S")
    df["timestamp_unix"] = df["unix_time"].astype(int)

    df["soil_now"] = df["soil_moisture_pct"].astype(float)
    df["temp_now"] = df["temperature_c"].astype(float)
    df["humidity_now"] = df["humidity_pct"].astype(float)
    df["light_now"] = df["light_level_pct"].astype(float)

    df["hour_of_day"] = df["timestamp_utc"].dt.hour.astype(int)
    df["day_of_week"] = df["timestamp_utc"].dt.dayofweek.astype(int)

    df["hour_sin"] = np.sin(2 * np.pi * df["hour_of_day"] / 24.0)
    df["hour_cos"] = np.cos(2 * np.pi * df["hour_of_day"] / 24.0)
    df["dow_sin"] = np.sin(2 * np.pi * df["day_of_week"] / 7.0)
    df["dow_cos"] = np.cos(2 * np.pi * df["day_of_week"] / 7.0)

    df["step_in_sequence"] = df.groupby(group_cols).cumcount().astype(int)

    group_id_map = {key: idx for idx, key in enumerate(df.groupby(group_cols).groups.keys())}
    df["sequence"] = [group_id_map[(pl, dev)] for pl, dev in zip(df["plant_label"], df["device_id"])]
    df["sequence"] = df["sequence"].astype(int)

    df["moisture_mean"] = (
        df.groupby(group_cols)["soil_now"]
        .transform(lambda s: s.rolling(window=4, min_periods=1).mean())
        .astype(float)
    )

    df["moisture_delta"] = (
        df.groupby(group_cols)["soil_now"]
        .diff()
        .fillna(0.0)
        .astype(float)
    )

    def _window_slope(series: pd.Series, window: int = 4) -> pd.Series:
        values = series.to_numpy(dtype=float)
        out = np.zeros(len(values), dtype=float)

        for i in range(len(values)):
            start = max(0, i - window + 1)
            n = i - start + 1
            if n <= 1:
                out[i] = 0.0
            else:
                out[i] = (values[i] - values[start]) / float(n - 1)

        return pd.Series(out, index=series.index)

    df["moisture_slope"] = (
        df.groupby(group_cols)["soil_now"]
        .transform(_window_slope)
        .astype(float)
    )

    df["dry_duration"] = 0.0
    for _, idx in df.groupby(group_cols, sort=False).groups.items():
        group_idx = list(idx)
        g = df.loc[group_idx].sort_values("timestamp_utc")

        is_dry = g["soil_now"] < 35.0
        dt_hours = g["timestamp_utc"].diff().dt.total_seconds().fillna(0.0) / 3600.0

        out = np.zeros(len(g), dtype=float)
        acc = 0.0

        for i, (dry, delta_h) in enumerate(zip(is_dry.to_numpy(), dt_hours.to_numpy())):
            delta_h = max(0.0, float(delta_h))
            if dry:
                acc += delta_h
            else:
                acc = 0.0
            out[i] = acc

        df.loc[g.index, "dry_duration"] = out

    df["dry_duration"] = df["dry_duration"].fillna(0.0).astype(float)

    temp_factor = clip01((df["temp_now"] - 20.0) / 15.0)
    humidity_factor = clip01((60.0 - df["humidity_now"]) / 40.0)
    light_factor = clip01((df["light_now"] - 200.0) / 700.0)

    evap_effect = (
        0.45 * temp_factor
        + 0.30 * humidity_factor
        + 0.25 * light_factor
    )

    df["combined_stress"] = (
        0.35 * clip01((40.0 - df["soil_now"]) / 40.0)
        + 0.25 * temp_factor
        + 0.20 * humidity_factor
        + 0.20 * light_factor
    ).astype(float)

    df["anomaly"] = (
        ((df["humidity_now"] < 20.0) & (df["temp_now"] > 32.0))
        | ((df["light_now"] < 70.0) & (df["temp_now"] > 34.0))
    ).astype(int)

    df["recovering"] = (
        (df["moisture_delta"] > 4.0) & (df["moisture_slope"] > 1.0)
    ).astype(int)

    low_soil = clip01((45.0 - df["soil_now"]) / 35.0)
    drying_trend = clip01((-df["moisture_slope"]) / 4.0)
    dryness_accum = clip01(df["dry_duration"] / 3.0)

    soil_drying_interaction = low_soil * drying_trend
    evap_dry_interaction = evap_effect * dryness_accum
    soil_evap_interaction = low_soil * evap_effect

    df["stress_score_proxy"] = (
        0.22 * low_soil
        + 0.18 * drying_trend
        + 0.16 * dryness_accum
        + 0.14 * evap_effect
        + 0.14 * soil_drying_interaction
        + 0.10 * evap_dry_interaction
        + 0.06 * soil_evap_interaction
    ).astype(float)

    return df


def print_comparison_summary(out: pd.DataFrame) -> None:
    """Print comparison info instead of writing separate CSVs."""
    if "logged_risk_class" not in out.columns:
        print("\nNo logged_risk_class column found; skipping comparison summary.")
        return

    out["risk_class_match"] = (
        pd.to_numeric(out["logged_risk_class"], errors="coerce")
        == pd.to_numeric(out["model_risk_class"], errors="coerce")
    )

    confusion = pd.crosstab(
        out["logged_risk_class"],
        out["model_risk_class"],
        rownames=["logged_risk_class"],
        colnames=["model_risk_class"],
        dropna=False,
    )

    mismatches = out.loc[~out["risk_class_match"]].copy()
    agreement = float(out["risk_class_match"].mean()) * 100.0

    print(f"\nRisk class agreement: {agreement:.2f}%")
    print("\nConfusion matrix:")
    print(confusion)

    print(f"\nMismatch rows: {len(mismatches)}")
    if not mismatches.empty:
        cols = [
            c for c in [
                "plant_label",
                "device_name",
                "timestamp_iso",
                "logged_risk_class",
                "model_risk_class",
                "logged_confidence",
                "model_confidence",
                "confidence_gap",
            ]
            if c in mismatches.columns
        ]
        print(mismatches[cols].to_string(index=False))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run model_export MLP on captured log CSV")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="Path to input log CSV")
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL, help="Path to model_export.json")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Path to output CSV")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    raw_df = pd.read_csv(args.input)
    fe_df = engineer_features(raw_df)

    cfg = json.loads(args.model.read_text(encoding="utf-8"))
    model = ExportedMLPModel(cfg)

    feature_order = cfg["feature_order"]
    missing_features = [f for f in feature_order if f not in fe_df.columns]
    if missing_features:
        raise ValueError(
            "Missing engineered features required by model: "
            f"{missing_features}\n\n"
            f"Available columns are:\n{list(fe_df.columns)}"
        )

    X = fe_df[feature_order].copy()

    probs = model.predict_proba(X)
    preds = model.predict(X)

    out = fe_df.copy()
    out["model_risk_class"] = preds
    out["model_confidence"] = probs.max(axis=1)

    classes = list(model.classes_)
    for cls_idx, cls_value in enumerate(classes):
        if int(cls_value) == 0:
            out["model_prob_healthy"] = probs[:, cls_idx]
        elif int(cls_value) == 1:
            out["model_prob_moderate_stress"] = probs[:, cls_idx]
        elif int(cls_value) == 2:
            out["model_prob_high_stress"] = probs[:, cls_idx]

    if "logged_confidence" in out.columns:
        out["confidence_gap"] = (
            out["model_confidence"] - pd.to_numeric(out["logged_confidence"], errors="coerce")
        )

    if "logged_risk_class" in out.columns:
        out["risk_class_match"] = (
            pd.to_numeric(out["logged_risk_class"], errors="coerce")
            == pd.to_numeric(out["model_risk_class"], errors="coerce")
        )

    keep_cols = [
        "plant_label",
        "device_name",
        "device_id",
        "timestamp_iso",
        "timestamp_unix",
        "hour_of_day",
        "day_of_week",
        "soil_now",
        "moisture_mean",
        "moisture_delta",
        "moisture_slope",
        "dry_duration",
        "temp_now",
        "humidity_now",
        "light_now",
        "combined_stress",
        "anomaly",
        "recovering",
        "sequence",
        "step_in_sequence",
        "hour_sin",
        "hour_cos",
        "dow_sin",
        "dow_cos",
        "stress_score_proxy",
        "logged_risk_class",
        "logged_confidence",
        "logged_prob_healthy",
        "logged_prob_moderate_stress",
        "logged_prob_high_stress",
        "model_risk_class",
        "model_confidence",
        "model_prob_healthy",
        "model_prob_moderate_stress",
        "model_prob_high_stress",
        "risk_class_match",
        "confidence_gap",
    ]

    available_keep = [c for c in keep_cols if c in out.columns]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    out[available_keep].to_csv(args.output, index=False)

    print(f"Input rows: {len(raw_df)}")
    print(f"Wrote predictions to: {args.output}")

    print("\nModel feature order:")
    print(feature_order)

    print("\nPredicted class distribution:")
    print(out["model_risk_class"].value_counts(normalize=True).sort_index())

    print_comparison_summary(out)


if __name__ == "__main__":
    main()