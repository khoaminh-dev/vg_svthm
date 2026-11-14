"""Xuất 2 model sức khoẻ (joblib) thành JSON thuần để API Node chạy mà không cần Python.

Dùng: python scripts/export_health_models.py <thư mục AI/models>
Ghi: api/_lib/health/models.ts và api/_tests/fixtures/health_parity.json
(parity: một loạt đầu vào ngẫu nhiên kèm xác suất do sklearn tính, để test TypeScript phải khớp).
"""
from __future__ import annotations

import json
import random
import sys
import warnings
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")
ROOT = Path(__file__).resolve().parent.parent


def medians(pipe):
    pre = pipe.named_steps["preprocessor"]
    num = pre.named_transformers_["numeric"]
    return [float(v) for v in num.named_steps["imputer"].statistics_], num


def export_logistic(bundle):
    pipe = bundle["pipeline"]
    med, num = medians(pipe)
    sc = num.named_steps["scaler"]
    clf = pipe.named_steps["model"]
    return {
        "kind": "logistic",
        "features": bundle["input_features"],
        "threshold": float(bundle["decision_threshold"]),
        "median": med,
        "mean": [float(v) for v in sc.mean_],
        "scale": [float(v) for v in sc.scale_],
        "coef": [float(v) for v in clf.coef_[0]],
        "intercept": float(clf.intercept_[0]),
    }


def export_hgb(bundle):
    pipe = bundle["pipeline"]
    med, _ = medians(pipe)
    clf = pipe.named_steps["model"]
    trees = []
    for it in clf._predictors:
        assert len(it) == 1
        nodes = it[0].nodes
        assert not nodes["is_categorical"].any()
        trees.append(
            {
                "f": [int(v) if not leaf else -1 for v, leaf in zip(nodes["feature_idx"], nodes["is_leaf"])],
                "t": [float(v) for v in nodes["num_threshold"]],
                "l": [int(v) for v in nodes["left"]],
                "r": [int(v) for v in nodes["right"]],
                "v": [float(v) for v in nodes["value"]],
                "m": [int(v) for v in nodes["missing_go_to_left"]],
            }
        )
    return {
        "kind": "hgb",
        "features": bundle["input_features"],
        "threshold": float(bundle["decision_threshold"]),
        "median": med,
        "baseline": float(np.ravel(clf._baseline_prediction)[0]),
        "trees": trees,
    }


def sample(rng, name, feats):
    row = {}
    for f in feats:
        if f == "age":
            row[f] = float(rng.randint(30, 90))
        elif f in ("sysBP",):
            row[f] = float(rng.randint(90, 200))
        elif f in ("diaBP",):
            row[f] = float(rng.randint(55, 125))
        elif f == "heartRate":
            row[f] = float(rng.randint(48, 120))
        else:
            row[f] = float(rng.randint(0, 1))
    return row


def main():
    models_dir = Path(sys.argv[1])
    stroke = joblib.load(models_dir / "03c_stroke_balanced_compact" / "model.joblib")
    heart = joblib.load(models_dir / "03b_heart_disease_bp_compact" / "model.joblib")
    out = {"stroke": export_logistic(stroke), "heart": export_hgb(heart)}
    target = ROOT / "api" / "_lib" / "health" / "models.ts"
    target.parent.mkdir(parents=True, exist_ok=True)
    header = "// Sinh tự động bởi scripts/export_health_models.py, không sửa tay.\nexport const HEALTH_MODELS: any = "
    target.write_text(header + json.dumps(out, separators=(",", ":")) + ";\n", encoding="utf-8")
    print("models.ts", target.stat().st_size, "bytes")

    rng = random.Random(7)
    cases = []
    for key, bundle in (("stroke", stroke), ("heart", heart)):
        for _ in range(60):
            row = sample(rng, key, bundle["input_features"])
            df = pd.DataFrame([row], columns=bundle["input_features"])
            p = float(bundle["pipeline"].predict_proba(df)[0][1])
            cases.append({"model": key, "input": row, "p": p})
    fx = ROOT / "api" / "_tests" / "fixtures"
    fx.mkdir(parents=True, exist_ok=True)
    (fx / "health_parity.json").write_text(json.dumps(cases), encoding="utf-8")
    print("parity cases", len(cases))


if __name__ == "__main__":
    main()
