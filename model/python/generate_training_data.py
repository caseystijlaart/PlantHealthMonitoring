"""Generate synthetic time-aware training data for POF-02.

Output: data/pof02_synthetic.csv

Sequences are long enough (300 steps x 10 min = 50 h) so that most starting
soil levels will cross the watering threshold within the sequence, giving a
real look-ahead label for the regression target (minutes_until_water).
"""

from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pandas as pd

OUT_DIR = Path(__file__).resolve().parent / "data"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_FILE = OUT_DIR / "pof02_synthetic.csv"

rng = np.random.default_rng(42)

STEP_MINUTES  = 180          # matches the real device's 3-hour sampling interval
SEQ_STEPS     = 120          # 15 days per sequence — covers realistic indoor-plant drying cycles
NUM_SEQUENCES = 200
WATER_THRESHOLD = 33.0       # must match PlantRuleProfile::soilMoistureThresholds.midMin

base_start = datetime(2026, 1, 1, 6, 0, tzinfo=timezone.utc)


def clip01(x: float) -> float:
    return float(np.clip(x, 0.0, 1.0))


rows = []

for seq in range(NUM_SEQUENCES):
    soil = rng.uniform(56, 88)   # start above midMax so sequences spend time in healthy range
    prev_soil = soil

    plant_sensitivity   = rng.uniform(0.8, 1.2)
    watering_event_step = int(rng.integers(30, 80)) if rng.random() < 0.25 else -1

    seq_start = base_start + timedelta(
        days=int(rng.integers(0, 80)),
        hours=int(rng.integers(0, 18)),
        minutes=int(rng.integers(0, 6)) * 10,
    )

    dry_steps  = 0
    soil_window: list[float] = []
    seq_rows: list[dict] = []

    for step in range(SEQ_STEPS):
        current_ts = seq_start + timedelta(minutes=step * STEP_MINUTES)
        hour = current_ts.hour
        dow  = current_ts.weekday()

        daylight_phase    = np.sin((hour - 6) / 12 * np.pi)
        daylight_strength = max(0.0, daylight_phase)

        light = np.clip(80 + 850 * daylight_strength + rng.normal(0, 70), 20, 1100)
        temp  = np.clip(19 + 9 * daylight_strength + rng.normal(0, 2.0)
                        + (0.8 if dow in [5, 6] else 0.0), 10, 40)
        humidity = np.clip(72 - 18 * daylight_strength + rng.normal(0, 5.0), 15, 100)

        temp_factor     = clip01((temp - 20) / 15)
        humidity_factor = clip01((60 - humidity) / 40)
        light_factor    = clip01((light - 200) / 700)

        evap_effect = 0.45 * temp_factor + 0.30 * humidity_factor + 0.25 * light_factor

        # Real indoor plants lose ~0.3–1.5 % soil moisture per 3-hour interval.
        # A watering event refills by 20–40 percentage points in one step.
        watering_boost = rng.uniform(20, 40) if step == watering_event_step else 0.0
        random_drift   = rng.normal(0, 0.4)

        soil_change = -plant_sensitivity * (0.42 + 1.65 * evap_effect) + watering_boost + random_drift
        soil = np.clip(soil + soil_change, 5, 95)

        soil_window.append(soil)
        if len(soil_window) > 4:
            soil_window.pop(0)

        moisture_mean  = float(np.mean(soil_window))
        moisture_delta = soil - prev_soil
        moisture_slope = (soil - soil_window[0]) / max(1, len(soil_window) - 1)

        if soil < 35:
            dry_steps += 1
        else:
            dry_steps = max(0, dry_steps - 1)

        dry_duration = dry_steps * STEP_MINUTES / 60.0

        low_soil              = clip01((55 - soil) / 35)  # 55 = midMax, matches PlantRuleProfile
        drying_trend          = clip01((-moisture_slope) / 4.0)
        dryness_accum         = clip01(dry_duration / 3.0)
        soil_drying_interaction = low_soil * drying_trend
        evap_dry_interaction  = evap_effect * dryness_accum
        soil_evap_interaction = low_soil * evap_effect
        combined_stress       = (0.35 * clip01((40 - soil) / 40) + 0.25 * temp_factor
                                  + 0.20 * humidity_factor + 0.20 * light_factor)

        stress_score = (
            0.22 * low_soil + 0.18 * drying_trend + 0.16 * dryness_accum
            + 0.14 * evap_effect + 0.14 * soil_drying_interaction
            + 0.10 * evap_dry_interaction + 0.06 * soil_evap_interaction
            + rng.normal(0, 0.04)
        )
        if watering_boost > 0:
            stress_score -= 0.18
        stress_score = float(np.clip(stress_score, 0.0, 1.2))

        risk     = 2 if stress_score > 0.62 else (1 if stress_score > 0.34 else 0)
        anomaly  = int((humidity < 20 and temp > 32) or (light < 70 and temp > 34))
        recovering = int(moisture_delta > 4 and moisture_slope > 1.0)

        seq_rows.append({
            "timestamp_iso":   current_ts.strftime("%Y-%m-%d %H:%M:%S"),
            "timestamp_unix":  int(current_ts.timestamp()),
            "hour_of_day":     hour,
            "day_of_week":     dow,
            "soil_now":        round(float(soil), 3),
            "moisture_mean":   round(float(moisture_mean), 3),
            "moisture_delta":  round(float(moisture_delta), 3),
            "moisture_slope":  round(float(moisture_slope), 3),
            "soil_x_slope":    round(float(soil) * float(moisture_slope), 3),
            "dry_duration":    round(float(dry_duration), 3),
            "temp_now":        round(float(temp), 3),
            "humidity_now":    round(float(humidity), 3),
            "light_now":       round(float(light), 3),
            "combined_stress": round(float(combined_stress), 3),
            "risk":            risk,
            "anomaly":         anomaly,
            "recovering":      recovering,
            "sequence":        seq,
            "step_in_sequence": step,
            "minutes_until_water": 0.0,   # filled in below
        })

        prev_soil = soil

    # --- Look-ahead: compute minutes_until_water for each step in this sequence ---
    soils = [r["soil_now"] for r in seq_rows]
    max_minutes = SEQ_STEPS * STEP_MINUTES   # cap for rows that never cross

    for i, row in enumerate(seq_rows):
        if soils[i] <= WATER_THRESHOLD:
            row["minutes_until_water"] = 0.0
            continue
        crossed = next(
            ((j - i) * STEP_MINUTES for j in range(i + 1, SEQ_STEPS)
             if soils[j] <= WATER_THRESHOLD),
            max_minutes   # threshold never crossed — use sequence cap
        )
        row["minutes_until_water"] = float(crossed)

    rows.extend(seq_rows)

df = pd.DataFrame(rows).sort_values("timestamp_unix").reset_index(drop=True)
df.to_csv(OUT_FILE, index=False)

print(f"Saved {len(df)} rows to {OUT_FILE}")
print(df[["timestamp_iso", "sequence", "step_in_sequence", "risk",
          "minutes_until_water"]].head(10))
print("\nClass distribution:")
print(df["risk"].value_counts(normalize=True).sort_index())
print("\nminutes_until_water stats:")
print(df["minutes_until_water"].describe())
