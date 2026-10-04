"""Model outputs -> Fields. `decode` is the logic the app ports: BIO tags to
character spans, best span per label, then the strict normalizers.

    uv run python -m hisab_ml.predict --model data/models/v1 --gold data/synthetic/test.jsonl --out preds.jsonl
    uv run python -m hisab_ml.predict --model data/models/v1 --onnx extractor.int8.onnx --text "Rs.450 debited ..."
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from . import normalize
from .features import SEQ_CLASSES, TAGS, prepare


def _softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - x.max(axis=-1, keepdims=True))
    return e / e.sum(axis=-1, keepdims=True)


def spans_from_tags(offsets, tag_probs: np.ndarray) -> list[tuple[str, int, int, float]]:
    """(label, start, end, mean token confidence). An I- tag that does not
    continue a span of its own label opens a new one."""
    out, cur = [], None

    def close():
        nonlocal cur
        if cur:
            label, s, e, ps = cur
            out.append((label, s, e, float(np.mean(ps))))
        cur = None

    for (s, e), probs in zip(offsets, tag_probs):
        if e <= s:
            close()
            continue
        k = int(probs.argmax())
        tag = TAGS[k]
        if tag == "O":
            close()
            continue
        prefix, label = tag.split("-", 1)
        if prefix == "I" and cur and cur[0] == label:
            cur[2] = e
            cur[3].append(float(probs[k]))
        else:
            close()
            cur = [label, s, e, [float(probs[k])]]
    close()
    return out


_NORMALIZE = {
    "AMOUNT": ("amount_paise", normalize.amount_paise),
    "BALANCE": ("balance_paise", normalize.amount_paise),
    "REF": ("ref", normalize.ref),
    "OWN_ACCT": ("own_acct_tail", normalize.acct_tail),
    "CPTY_ACCT": ("cpty_acct_tail", normalize.acct_tail),
    "DATE": ("date_iso", normalize.date_iso),
    "PAYEE": ("payee", lambda s: s.strip() or None),
    "VPA": ("vpa", lambda s: s.strip().lower() or None),
}


def clean_edges(text: str, start: int, end: int) -> bool:
    """A value is a whole run of digits or letters, never a slice of one. The
    model can otherwise tag the last 12 digits of a 20-character mandate id
    (HDFC7020902210002459) as a UPI reference — every digit verbatim, and
    still invented."""
    n = len(text)

    def splits_run(i: int) -> bool:
        if i <= 0 or i >= n:
            return False
        a, b = text[i - 1], text[i]
        return (a.isdigit() and b.isdigit()) or (a.isalpha() and b.isalpha())

    def splits_number(i: int) -> bool:
        # 3,13,938.00 is one number: no edge next to a separator between digits.
        if 2 <= i < n and text[i - 1] in ",." and text[i - 2].isdigit() and text[i].isdigit():
            return True
        return 1 <= i < n - 1 and text[i] in ",." and text[i - 1].isdigit() and text[i + 1].isdigit()

    # A value may START at a letter->digit edge (INR450) but may not END
    # inside a word: the 984 of a masked PAN "XXXXXX984D" is not an account.
    ends_inside_word = 0 < end < n and text[end - 1].isalnum() and text[end].isalnum()
    return not (splits_run(start) or splits_number(start) or splits_number(end) or ends_inside_word)


def decode(text: str, offsets, tag_logits: np.ndarray, seq_logits: np.ndarray) -> dict:
    seq = _softmax(seq_logits)
    cls = SEQ_CLASSES[int(seq.argmax())]
    fields: dict = {"is_txn": cls != "none", "conf": {"class": round(float(seq.max()), 4)}}
    if cls == "none":
        return fields
    fields["direction"] = cls
    best: dict[str, tuple[int, int, float]] = {}
    for label, s, e, p in spans_from_tags(offsets, _softmax(tag_logits)):
        if not clean_edges(text, s, e):
            continue
        if label not in best or p > best[label][2]:
            best[label] = (s, e, p)
    for label, (s, e, p) in best.items():
        key, fn = _NORMALIZE[label]
        value = fn(text[s:e])
        if value is not None:
            fields[key] = value
            fields["conf"][key] = round(p, 4)
    # Admission rule: a movement with no readable amount cannot be booked, so
    # it is not a transaction — whatever the class head says.
    if not fields.get("amount_paise"):
        return {"is_txn": False, "conf": {"class": fields["conf"]["class"]}}
    return fields


class TorchBackend:
    def __init__(self, model, tok, max_len: int, device: str = "cpu"):
        import torch
        self.torch, self.model, self.tok, self.max_len, self.device = torch, model.to(device), tok, max_len, device

    def __call__(self, texts: list[str]):
        enc = self.tok([prepare(t) for t in texts], return_offsets_mapping=True, truncation=True,
                       max_length=self.max_len, padding=True, return_tensors="pt")
        with self.torch.no_grad():
            tags, seq = self.model(enc["input_ids"].to(self.device), enc["attention_mask"].to(self.device))
        return enc["offset_mapping"].tolist(), tags.float().cpu().numpy(), seq.float().cpu().numpy()


class OnnxBackend:
    def __init__(self, path: Path, tok, max_len: int, threads: int = 2):
        import onnxruntime as ort
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = threads
        self.session = ort.InferenceSession(str(path), opts, providers=["CPUExecutionProvider"])
        self.tok, self.max_len = tok, max_len

    def __call__(self, texts: list[str]):
        enc = self.tok([prepare(t) for t in texts], return_offsets_mapping=True, truncation=True,
                       max_length=self.max_len, padding=True, return_tensors="np")
        tags, seq = self.session.run(None, {"input_ids": enc["input_ids"].astype(np.int64),
                                            "attention_mask": enc["attention_mask"].astype(np.int64)})
        return enc["offset_mapping"].tolist(), tags, seq


def predict_texts(backend, texts: list[str], batch: int = 64) -> list[dict]:
    out = []
    for i in range(0, len(texts), batch):
        chunk = texts[i:i + batch]
        offsets, tags, seq = backend(chunk)
        out.extend(decode(t, o, tg, sq) for t, o, tg, sq in zip(chunk, offsets, tags, seq))
    return out


def main() -> None:
    from .evaluate import format_report, load_gold, score
    from .model import load

    ap = argparse.ArgumentParser()
    ap.add_argument("--model", type=Path, required=True)
    ap.add_argument("--onnx", help="score this ONNX file in the model dir instead of the torch weights")
    ap.add_argument("--gold", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--text", help="predict one alert and print its fields")
    args = ap.parse_args()

    model, tok, meta = load(args.model)
    backend = (OnnxBackend(args.model / args.onnx, tok, meta["max_len"]) if args.onnx
               else TorchBackend(model, tok, meta["max_len"]))
    if args.text:
        print(json.dumps(predict_texts(backend, [args.text])[0], indent=2, ensure_ascii=False))
        return
    gold = load_gold(args.gold)
    preds = predict_texts(backend, [r.text for r in gold])
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text("".join(json.dumps({"id": r.id, "fields": p}) + "\n" for r, p in zip(gold, preds)))
    print(format_report(score(gold, {r.id: p for r, p in zip(gold, preds)})))


if __name__ == "__main__":
    main()
