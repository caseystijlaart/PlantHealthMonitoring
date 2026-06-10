"""Export helper artifacts for TinyML deployment.

Creates:
- data/features_for_edge_impulse.csv
- data/model_export.h
"""

from pathlib import Path
import json

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
MODEL_FILE = DATA_DIR / "model_export.json"
RAW_FILE = DATA_DIR / "pof02_synthetic.csv"

EDGE_FILE = DATA_DIR / "features_for_edge_impulse.csv"
HEADER_FILE = DATA_DIR / "model_export.h"


def ensure_time_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add cyclical time features if they are missing."""
    if "hour_sin" not in df.columns and "hour_of_day" in df.columns:
        df["hour_sin"] = np.sin(2 * np.pi * df["hour_of_day"] / 24.0)

    if "hour_cos" not in df.columns and "hour_of_day" in df.columns:
        df["hour_cos"] = np.cos(2 * np.pi * df["hour_of_day"] / 24.0)

    if "dow_sin" not in df.columns and "day_of_week" in df.columns:
        df["dow_sin"] = np.sin(2 * np.pi * df["day_of_week"] / 7.0)

    if "dow_cos" not in df.columns and "day_of_week" in df.columns:
        df["dow_cos"] = np.cos(2 * np.pi * df["day_of_week"] / 7.0)

    return df


cfg = json.loads(MODEL_FILE.read_text(encoding="utf-8"))
df = pd.read_csv(RAW_FILE)
df = ensure_time_features(df)

feature_order = cfg["feature_order"]

required_columns = ["timestamp_iso", "timestamp_unix"] + feature_order + ["risk", "anomaly", "recovering"]
missing_columns = [col for col in required_columns if col not in df.columns]

if missing_columns:
    raise ValueError(f"Missing required columns in dataset: {missing_columns}")

# 1) CSV that can be imported into Edge Impulse Studio as tabular data.
df[required_columns].to_csv(EDGE_FILE, index=False)

# 2) C header for embedded preprocessing alignment.
means = ", ".join(f"{x:.8f}f" for x in cfg["scaler"]["mean"])
stds = ", ".join(f"{x:.8f}f" for x in cfg["scaler"]["std"])
feature_names = ", ".join(f'"{f}"' for f in feature_order)

header = (
    "#pragma once\n\n"
    f"static constexpr int POF02_FEATURE_COUNT = {len(feature_order)};\n"
    f"static constexpr const char* POF02_FEATURE_ORDER[{len(feature_order)}] = {{ {feature_names} }};\n\n"
    f"static constexpr float POF02_SCALER_MEAN[{len(feature_order)}] = {{ {means} }};\n"
    f"static constexpr float POF02_SCALER_STD[{len(feature_order)}] = {{ {stds} }};\n"
)

HEADER_FILE.write_text(header, encoding="utf-8")

print(f"Wrote {EDGE_FILE}")
print(f"Wrote {HEADER_FILE}")