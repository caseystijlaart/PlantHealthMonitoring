import pandas as pd
import numpy as np

from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier, IsolationForest
from sklearn.neural_network import MLPClassifier, MLPRegressor
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    mean_squared_error,
    mean_absolute_error,
    r2_score,
)

def validate_required_columns(data, feature_columns, target_column):
    required_columns = feature_columns + [target_column]
    missing_columns = [col for col in required_columns if col not in data.columns]
    if missing_columns:
        raise ValueError(f"Dataset is missing required columns: {missing_columns}")
    return required_columns

def prepare_dataset(data, feature_columns, target_column):
    required_columns = validate_required_columns(data, feature_columns, target_column)
    dataset = data[required_columns].copy()
    dataset = dataset.dropna()
    return dataset

def run_random_forest_baseline(dataset, feature_columns, target_column):
    x = dataset[feature_columns]
    y = dataset[target_column]

    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=0.2, random_state=42, stratify=y
    )

    model = RandomForestClassifier(random_state=42)
    model.fit(x_train, y_train)

    test_pred = model.predict(x_test)

    return {
        "model": "RandomForest",
        "accuracy": accuracy_score(y_test, test_pred)
    }

def run_tiny_classifier(dataset, feature_columns, target_column):
    x = dataset[feature_columns]
    y = dataset[target_column]

    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=0.2, random_state=42, stratify=y
    )

    model = MLPClassifier(hidden_layer_sizes=(8,), max_iter=500, random_state=42)
    model.fit(x_train, y_train)

    test_pred = model.predict(x_test)

    return {
        "model": "TinyMLP",
        "accuracy": accuracy_score(y_test, test_pred)
    }

def run_tiny_regression(dataset, feature_columns, target_column, mapping):
    x = dataset[feature_columns]
    y = dataset[target_column].map(mapping)

    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=0.2, random_state=42
    )

    model = MLPRegressor(hidden_layer_sizes=(8,), max_iter=500, random_state=42)
    model.fit(x_train, y_train)

    pred = model.predict(x_test)

    return {
        "model": "TinyRegression",
        "mse": mean_squared_error(y_test, pred),
        "mae": mean_absolute_error(y_test, pred),
        "r2": r2_score(y_test, pred)
    }

def run_anomaly_detection(dataset, feature_columns, target_column, normal_label):
    normal_data = dataset[dataset[target_column] == normal_label]

    model = IsolationForest(contamination=0.1, random_state=42)
    model.fit(normal_data[feature_columns])

    preds = model.predict(dataset[feature_columns])
    anomaly_count = np.sum(preds == -1)

    return {
        "model": "AnomalyDetection",
        "anomaly_count": int(anomaly_count)
    }

def compare_dataset(data, name, feature_columns, target_column, mapping=None, normal_label=None):
    dataset = prepare_dataset(data, feature_columns, target_column)

    results = []

    results.append(run_random_forest_baseline(dataset, feature_columns, target_column))
    results.append(run_tiny_classifier(dataset, feature_columns, target_column))

    if mapping:
        results.append(run_tiny_regression(dataset, feature_columns, target_column, mapping))

    if normal_label:
        results.append(run_anomaly_detection(dataset, feature_columns, target_column, normal_label))

    df = pd.DataFrame(results)
    df["dataset"] = name

    return df
