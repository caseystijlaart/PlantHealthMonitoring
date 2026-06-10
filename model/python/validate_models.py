"""Validation script comparing rule-based risk to exported MLP outputs,
including manual permutation importance and SHAP plots."""

from pathlib import Path
import json

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix


ROOT = Path(__file__).resolve().parent
DATA_FILE = ROOT / "data" / "pof02_synthetic.csv"
MODEL_FILE = ROOT / "data" / "model_export.json"
OUT_DIR = ROOT / "data"
PLOT_DIR = OUT_DIR / "plots"
PLOT_DIR.mkdir(parents=True, exist_ok=True)


def rule_based_risk(row: pd.Series) -> int:
    if row["soil_now"] < 30 and row["moisture_slope"] < -1.5:
        return 2
    if row["combined_stress"] > 0.25 or row["dry_duration"] > 4:
        return 1
    return 0


def relu(x: np.ndarray) -> np.ndarray:
    return np.maximum(x, 0.0)


def softmax(x: np.ndarray) -> np.ndarray:
    z = x - np.max(x, axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


class ExportedMLPModel:
    """Inference wrapper around exported scaler + MLP weights."""

    def __init__(self, cfg: dict):
        self.feature_order = cfg["feature_order"]
        self.mean = np.array(cfg["scaler"]["mean"], dtype=float)
        self.std = np.array(cfg["scaler"]["std"], dtype=float)

        # Avoid division by zero if any std accidentally becomes 0
        self.std[self.std == 0] = 1.0

        self.W1 = np.array(cfg["mlp"]["coefs"][0], dtype=float)
        self.W2 = np.array(cfg["mlp"]["coefs"][1], dtype=float)
        self.b1 = np.array(cfg["mlp"]["intercepts"][0], dtype=float)
        self.b2 = np.array(cfg["mlp"]["intercepts"][1], dtype=float)
        self.classes_ = np.array(cfg["mlp"]["classes"], dtype=int)

    def _prepare_X(self, X) -> np.ndarray:
        if isinstance(X, pd.DataFrame):
            X = X[self.feature_order].to_numpy(dtype=float)
        else:
            X = np.asarray(X, dtype=float)
        return X

    def predict_proba(self, X) -> np.ndarray:
        X = self._prepare_X(X)
        Xn = (X - self.mean) / self.std
        hidden = relu(Xn @ self.W1 + self.b1)
        logits = hidden @ self.W2 + self.b2
        return softmax(logits)

    def predict(self, X) -> np.ndarray:
        probs = self.predict_proba(X)
        indices = np.argmax(probs, axis=1)
        return self.classes_[indices]


def ensure_time_features(df: pd.DataFrame) -> pd.DataFrame:
    """Ensure cyclical time features exist if base columns are present."""
    if "hour_sin" not in df.columns and "hour_of_day" in df.columns:
        df["hour_sin"] = np.sin(2 * np.pi * df["hour_of_day"] / 24.0)
    if "hour_cos" not in df.columns and "hour_of_day" in df.columns:
        df["hour_cos"] = np.cos(2 * np.pi * df["hour_of_day"] / 24.0)
    if "dow_sin" not in df.columns and "day_of_week" in df.columns:
        df["dow_sin"] = np.sin(2 * np.pi * df["day_of_week"] / 7.0)
    if "dow_cos" not in df.columns and "day_of_week" in df.columns:
        df["dow_cos"] = np.cos(2 * np.pi * df["day_of_week"] / 7.0)
    return df


def manual_permutation_importance(
    model: ExportedMLPModel,
    X_df: pd.DataFrame,
    y_true: np.ndarray,
    n_repeats: int = 10,
    random_state: int = 7,
) -> pd.DataFrame:
    """Compute permutation importance manually using accuracy drop."""
    rng = np.random.default_rng(random_state)
    baseline_pred = model.predict(X_df)
    baseline_acc = accuracy_score(y_true, baseline_pred)

    rows = []

    for feature in X_df.columns:
        drops = []

        for _ in range(n_repeats):
            X_perm = X_df.copy()
            X_perm[feature] = rng.permutation(X_perm[feature].to_numpy())

            perm_pred = model.predict(X_perm)
            perm_acc = accuracy_score(y_true, perm_pred)
            drops.append(baseline_acc - perm_acc)

        rows.append(
            {
                "feature": feature,
                "importance_mean": float(np.mean(drops)),
                "importance_std": float(np.std(drops)),
            }
        )

    return pd.DataFrame(rows).sort_values("importance_mean", ascending=False)


def save_permutation_plot(perm_df: pd.DataFrame, out_path: Path) -> None:
    plt.figure(figsize=(10, 6))
    plt.barh(perm_df["feature"], perm_df["importance_mean"])
    plt.xlabel("Mean accuracy drop after permutation")
    plt.ylabel("Feature")
    plt.title("Permutation Importance - Exported MLP")
    plt.gca().invert_yaxis()
    plt.tight_layout()
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()


def save_confusion_matrix_plot(cm: np.ndarray, labels: list[int], out_path: Path) -> None:
    plt.figure(figsize=(6, 5))
    plt.imshow(cm, interpolation="nearest")
    plt.title("Confusion Matrix - Exported MLP")
    plt.colorbar()
    tick_marks = np.arange(len(labels))
    plt.xticks(tick_marks, labels)
    plt.yticks(tick_marks, labels)
    plt.xlabel("Predicted label")
    plt.ylabel("True label")

    for i in range(cm.shape[0]):
        for j in range(cm.shape[1]):
            plt.text(j, i, str(cm[i, j]), ha="center", va="center")

    plt.tight_layout()
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()


def try_generate_shap_plots(
    model: ExportedMLPModel,
    X_df: pd.DataFrame,
    plot_dir: Path,
    random_state: int = 7,
) -> None:
    """Attempt SHAP analysis. If unavailable/failing, continue gracefully."""
    try:
        import shap  # type: ignore
    except ImportError:
        print("SHAP not installed. Skipping SHAP plots.")
        return

    try:
        max_background = min(len(X_df), 100)
        max_explain = min(len(X_df), 200)

        background_df = X_df.sample(n=max_background, random_state=random_state)
        explain_df = X_df.sample(n=max_explain, random_state=random_state)

        explainer = shap.Explainer(model.predict_proba, background_df)
        shap_values = explainer(explain_df)

        num_classes = shap_values.values.shape[2]

        for class_idx in range(num_classes):
            # Summary plot
            plt.figure()
            shap.summary_plot(
                shap_values.values[:, :, class_idx],
                explain_df,
                show=False,
            )
            plt.tight_layout()
            summary_path = plot_dir / f"shap_summary_class_{class_idx}.png"
            plt.savefig(summary_path, dpi=200, bbox_inches="tight")
            plt.close()
            print(f"Saved SHAP summary plot to {summary_path}")

            # Mean absolute SHAP bar data + plot
            mean_abs_shap = np.abs(shap_values.values[:, :, class_idx]).mean(axis=0)

            shap_bar_df = pd.DataFrame(
                {
                    "feature": X_df.columns,
                    "mean_abs_shap": mean_abs_shap,
                }
            ).sort_values("mean_abs_shap", ascending=False)

            shap_csv_path = OUT_DIR / f"shap_mean_abs_class_{class_idx}.csv"
            shap_bar_df.to_csv(shap_csv_path, index=False)
            print(f"Saved SHAP values to {shap_csv_path}")

            plt.figure(figsize=(10, 6))
            plt.barh(shap_bar_df["feature"], shap_bar_df["mean_abs_shap"])
            plt.xlabel("Mean |SHAP value|")
            plt.ylabel("Feature")
            plt.title(f"SHAP Feature Importance - Class {class_idx}")
            plt.gca().invert_yaxis()
            plt.tight_layout()
            shap_bar_path = plot_dir / f"shap_bar_class_{class_idx}.png"
            plt.savefig(shap_bar_path, dpi=200, bbox_inches="tight")
            plt.close()
            print(f"Saved SHAP bar plot to {shap_bar_path}")

    except Exception as exc:
        print(f"SHAP generation failed, skipping SHAP plots. Reason: {exc}")


def main() -> None:
    df = pd.read_csv(DATA_FILE)
    df = ensure_time_features(df)

    cfg = json.loads(MODEL_FILE.read_text(encoding="utf-8"))
    feature_order = cfg["feature_order"]

    missing_features = [f for f in feature_order if f not in df.columns]
    if missing_features:
        raise ValueError(f"Missing required features in CSV: {missing_features}")

    X_df = df[feature_order].copy()
    true_y = df["risk"].to_numpy()

    model = ExportedMLPModel(cfg)

    mlp_probs = model.predict_proba(X_df)
    mlp_pred = model.predict(X_df)
    rule_pred = df.apply(rule_based_risk, axis=1).to_numpy()

    rule_acc = accuracy_score(true_y, rule_pred)
    mlp_acc = accuracy_score(true_y, mlp_pred)

    print("Rule-based accuracy:", round(float(rule_acc), 4))
    print("MLP accuracy:       ", round(float(mlp_acc), 4))

    print("\n=== Exported MLP Classification Report ===")
    print(classification_report(true_y, mlp_pred, digits=3))

    summary = pd.DataFrame(
        {
            "timestamp_iso": df["timestamp_iso"] if "timestamp_iso" in df.columns else "",
            "true": true_y,
            "rule": rule_pred,
            "mlp": mlp_pred,
            "mlp_confidence": mlp_probs.max(axis=1),
        }
    )

    out_file = OUT_DIR / "validation_comparison.csv"
    summary.to_csv(out_file, index=False)
    print(f"Saved detailed comparison to {out_file}")

    # Save misclassified rows
    misclassified = summary[summary["true"] != summary["mlp"]].copy()
    misclassified_file = OUT_DIR / "mlp_misclassified.csv"
    misclassified.to_csv(misclassified_file, index=False)
    print(f"Saved misclassified rows to {misclassified_file}")

    # Confusion matrix
    labels = sorted(np.unique(true_y).tolist())
    cm = confusion_matrix(true_y, mlp_pred, labels=labels)
    cm_df = pd.DataFrame(cm, index=[f"true_{x}" for x in labels], columns=[f"pred_{x}" for x in labels])
    cm_file = OUT_DIR / "confusion_matrix.csv"
    cm_df.to_csv(cm_file)
    print(f"Saved confusion matrix to {cm_file}")

    cm_plot_file = PLOT_DIR / "confusion_matrix.png"
    save_confusion_matrix_plot(cm, labels, cm_plot_file)
    print(f"Saved confusion matrix plot to {cm_plot_file}")

    # Manual permutation importance
    perm_df = manual_permutation_importance(model, X_df, true_y, n_repeats=10, random_state=7)
    perm_file = OUT_DIR / "permutation_importance.csv"
    perm_df.to_csv(perm_file, index=False)
    print(f"Saved permutation importance to {perm_file}")

    perm_plot_file = PLOT_DIR / "permutation_importance.png"
    save_permutation_plot(perm_df, perm_plot_file)
    print(f"Saved permutation importance plot to {perm_plot_file}")

    # SHAP
    try_generate_shap_plots(model, X_df, PLOT_DIR, random_state=7)


if __name__ == "__main__":
    main()