"""Export a trained extractor to ONNX, quantize to int8, and re-score both.

    uv run python -m hisab_ml.export --model data/models/v1 --gold data/synthetic/test.jsonl

Writes extractor.onnx (fp32) and extractor.int8.onnx next to the weights. The
int8 file is what ships; it must score like the torch model before it does.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import torch

from .evaluate import format_report, load_gold, score
from .model import load
from .predict import OnnxBackend, predict_texts


def export(model_dir: Path) -> tuple[Path, Path]:
    from onnxruntime.quantization import QuantType, quantize_dynamic

    model, tok, _ = load(model_dir)
    sample = tok(["Rs.450.00 debited from a/c XX1234 to VPA a@okaxis"], return_tensors="pt")
    fp32, int8 = model_dir / "extractor.onnx", model_dir / "extractor.int8.onnx"
    torch.onnx.export(
        model, (sample["input_ids"], sample["attention_mask"]), str(fp32),
        input_names=["input_ids", "attention_mask"], output_names=["tag_logits", "seq_logits"],
        dynamic_axes={"input_ids": {0: "batch", 1: "seq"}, "attention_mask": {0: "batch", 1: "seq"},
                      "tag_logits": {0: "batch", 1: "seq"}, "seq_logits": {0: "batch"}},
        opset_version=17, dynamo=False,
    )
    quantize_dynamic(str(fp32), str(int8), weight_type=QuantType.QInt8)
    return fp32, int8


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", type=Path, required=True)
    ap.add_argument("--gold", type=Path, required=True)
    args = ap.parse_args()

    fp32, int8 = export(args.model)
    _, tok, meta = load(args.model)
    gold = load_gold(args.gold)
    for path in (fp32, int8):
        preds = predict_texts(OnnxBackend(path, tok, meta["max_len"]), [r.text for r in gold])
        print(f"{path.name}: {path.stat().st_size / 1e6:.1f} MB")
        print(format_report(score(gold, {r.id: p for r, p in zip(gold, preds)})))


if __name__ == "__main__":
    main()
