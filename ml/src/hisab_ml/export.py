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


class _Traceable(torch.nn.Module):
    """The Extractor with a plain additive attention mask. transformers 5
    builds its mask with ops coremltools cannot convert (`new_ones`); the
    layers themselves are unchanged, and export checks the outputs agree."""

    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, input_ids, attention_mask):
        enc = self.m.encoder
        h = enc.embeddings(input_ids=input_ids)
        if hasattr(enc, "embeddings_project"):
            h = enc.embeddings_project(h)
        # -1e4 rather than -inf or finfo.min: the iOS model runs in float16.
        mask = (1.0 - attention_mask[:, None, None, :].to(h.dtype)) * -1e4
        for layer in enc.encoder.layer:
            out = layer(h, attention_mask=mask)
            h = out[0] if isinstance(out, tuple) else out
        return self.m.tag_head(h), self.m.seq_head(h[:, 0])


def export_coreml(model_dir: Path) -> Path:
    """Core ML for iOS: int8 weights, compiled to .mlmodelc so it loads with no
    Xcode build step (SwiftPM on the command line does not compile models)."""
    import subprocess

    import coremltools as ct
    import numpy as np
    from coremltools.optimize.coreml import OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights

    model, tok, meta = load(model_dir)
    model.encoder.config._attn_implementation = "eager"
    wrapped = _Traceable(model).eval()
    sample = tok(["Rs.450.00 debited from a/c XX1234 to VPA a@okaxis", "Sent Rs.239.00\nTo SWIGGY"],
                 return_tensors="pt", padding=True)
    with torch.no_grad():
        want, got = model(sample["input_ids"], sample["attention_mask"]), wrapped(sample["input_ids"],
                                                                                  sample["attention_mask"])
    gap = max((a - b).abs().max().item() for a, b in zip(want, got))
    assert gap < 1e-3, f"wrapper disagrees with the model by {gap}"
    one = {k: v[:1] for k, v in sample.items()}
    traced = torch.jit.trace(wrapped, (one["input_ids"], one["attention_mask"]), strict=False)
    seq = ct.RangeDim(lower_bound=2, upper_bound=meta["max_len"], default=64)
    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input_ids", shape=(1, seq), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, seq), dtype=np.int32)],
        outputs=[ct.TensorType(name="tag_logits"), ct.TensorType(name="seq_logits")],
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
    )
    ml = linear_quantize_weights(ml, OptimizationConfig(global_config=OpLinearQuantizerConfig(
        mode="linear_symmetric", weight_threshold=512)))
    package = model_dir / "Extractor.mlpackage"
    ml.save(str(package))
    subprocess.run(["xcrun", "coremlcompiler", "compile", str(package), str(model_dir)], check=True,
                   capture_output=True)
    return model_dir / "Extractor.mlmodelc"


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
