"""Rebuild a checkpoint directory from the shipped Core ML model.

    uv run python -m hisab_ml.recover --out data/models/recovered

The training data and the torch checkpoints were lost on 2026-10-05, so the
compiled `Extractor.mlmodelc` in HisabCore is the model's source of truth. Its
MIL names every weight after the torch parameter it was traced from
(`m_encoder_..._weight_to_fp16`); linear and embedding weights are int8 with an
fp16 scale (`constexpr_blockwise_shift_scale`), everything else is fp16. The
output directory has the layout `model.load` reads, so `export` and `fixtures`
run on it unchanged.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

import numpy as np
import torch
from coremltools.libmilstoragepython import _BlobStorageReader
from transformers import AutoConfig, AutoModel, AutoTokenizer

from .features import SEQ_CLASSES, TAGS
from .model import Extractor

REPO = Path(__file__).resolve().parents[3]
MLMODELC = REPO / "HisabCore/Sources/HisabCore/Resources/extractor/Extractor.mlmodelc"
BASE = "google/electra-small-discriminator"

# A tensor value: a blob in weight.bin, or (small tensors) an inline literal.
_VALUE = r'tensor<(\w+), \[([\d, ]*)\]>\((BLOBFILE\(path = string\("[^"]*"\), offset = uint64\(\d+\)\)|[^()]*)\)'
CONST = re.compile(r"tensor<fp16, \[[\d, ]*\]> (\w+) = const\(\)\[name = string\(\"\w+\"\), val = " + _VALUE)
QUANT = re.compile(r"tensor<fp16, \[[\d, ]*\]> (\w+) = constexpr_blockwise_shift_scale\(data = " + _VALUE
                   + r", scale = " + _VALUE + r"\)")
_NUMBER = re.compile(r"-?0x[0-9a-fA-F.]+p[-+]?\d+|-?\d+(?:\.\d*)?(?:e[-+]?\d+)?")


def _value(blobs, dtype: str, shape: str, body: str) -> np.ndarray:
    dims = tuple(int(x) for x in shape.split(",")) if shape.strip() else ()
    if body.startswith("BLOBFILE"):
        offset = int(re.search(r"uint64\((\d+)\)", body).group(1))
        if dtype == "fp16":
            flat = np.array(blobs.read_fp16_data(offset), dtype=np.uint16).view(np.float16).astype(np.float32)
        elif dtype == "int8":
            flat = np.array(blobs.read_int8_data(offset), dtype=np.int8).astype(np.float32)
        else:
            raise ValueError(f"unexpected blob dtype {dtype}")
    else:
        flat = np.array([float.fromhex(t) if "0x" in t else float(t) for t in _NUMBER.findall(body)],
                        dtype=np.float32)
    return flat.reshape(dims)


def read_weights(mlmodelc: Path = MLMODELC) -> dict[str, np.ndarray]:
    """Every fp16 constant and dequantized int8 weight, keyed by MIL name with
    the `_to_fp16` / `_quantized` suffixes removed."""
    mil = (mlmodelc / "model.mil").read_text()
    blobs = _BlobStorageReader(str(mlmodelc / "weights/weight.bin"))
    out: dict[str, np.ndarray] = {}
    for name, *value in CONST.findall(mil):
        out[name.removesuffix("_to_fp16")] = _value(blobs, *value)
    for name, *values in QUANT.findall(mil):
        data, scale = _value(blobs, *values[:3]), _value(blobs, *values[3:])
        # The runtime dequantizes in fp16; round the same way.
        out[name.removesuffix("_quantized").removesuffix("_to_fp16")] = (data * scale).astype(np.float16).astype(np.float32)
    return out


def recover(out: Path, max_len: int = 192) -> Extractor:
    weights = read_weights()
    model = Extractor(AutoModel.from_config(AutoConfig.from_pretrained(BASE)))
    state = model.state_dict()
    loaded, missing = {}, []
    for key, tensor in state.items():
        mil = "m_" + key.replace(".", "_")
        if mil in weights and weights[mil].shape == tuple(tensor.shape):
            loaded[key] = torch.from_numpy(weights[mil])
        else:
            missing.append(key)
    # The trace folds token type 0 and the position slice into constants the
    # model never needs as parameters; anything else missing is a real gap.
    tolerated = {"encoder.embeddings.token_type_embeddings.weight", "encoder.embeddings.position_ids",
                 "encoder.embeddings.token_type_ids"}
    gaps = [k for k in missing if k not in tolerated]
    if gaps:
        raise SystemExit(f"no MIL weight for {gaps}")
    for k in missing:
        print(f"  not in MIL (folded by the trace): {k}")
    state.update(loaded)
    model.load_state_dict(state)
    model.eval()

    out.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out / "model.pt")
    model.encoder.config.save_pretrained(out / "encoder")
    shutil.rmtree(out / "tokenizer", ignore_errors=True)
    AutoTokenizer.from_pretrained(BASE).save_pretrained(out / "tokenizer")
    (out / "meta.json").write_text(json.dumps({
        "base": BASE, "max_len": max_len, "recovered_from": str(MLMODELC.relative_to(REPO)),
        "tags": TAGS, "seq_classes": SEQ_CLASSES}, indent=2) + "\n")
    print(f"recovered {len(loaded)} tensors -> {out}")
    return model


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    recover(ap.parse_args().out)


if __name__ == "__main__":
    main()
