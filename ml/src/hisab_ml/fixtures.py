"""Ship the extractor to the apps: artifacts + parity fixtures.

    uv run python -m hisab_ml.fixtures --model data/models/v4

Writes into the repo (paths relative to ml/):
  ../HisabCore/Sources/HisabCore/Resources/extractor/
      vocab.txt  chartable.json  extractor.json  Extractor.mlmodelc/
  ../hisab_flutter/assets/extractor/extractor.int8.onnx
  ../HisabCore/Tests/HisabCoreTests/Fixtures/extractor-{tokenizer,normalize,decode,model}.json

tool/sync_assets.sh mirrors the shared files into the Flutter app and the Dart
tests. Fixture texts are synthetic or hand-written: real alerts never enter
the repository.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
from pathlib import Path

import numpy as np

from . import normalize
from .compose import compose
from .evaluate import load_gold
from .features import SEQ_CLASSES, TAGS, prepare
from .generate import make_record
from .model import load
from .predict import CoreMLBackend, OnnxBackend, clean_edges, decode
from .wordpiece import EDGE_CASES, Table, build_table, encode, load_vocab, write_vocab_txt

REPO = Path(__file__).resolve().parents[3]
RESOURCES = REPO / "HisabCore/Sources/HisabCore/Resources/extractor"
FIXTURES = REPO / "HisabCore/Tests/HisabCoreTests/Fixtures"
FLUTTER_ASSETS = REPO / "hisab_flutter/assets/extractor"
FIELDS = ("is_txn", "direction", "amount_paise", "ref", "payee", "vpa", "own_acct_tail", "cpty_acct_tail",
          "date_iso", "balance_paise")


def _texts(n: int, seed: int) -> list[str]:
    """Synthetic alerts: held-out hand templates and compositional ones."""
    rng = random.Random(seed)
    test = [r.text for r in load_gold(Path("data/synthetic-v4/test.jsonl"))]
    rng.shuffle(test)
    composed = [make_record(compose(rng), i, rng).text for i in range(n)]
    return test[: n // 2] + composed[: n - n // 2]


def _fields(d: dict) -> dict:
    return {k: d.get(k) for k in FIELDS if d.get(k) is not None} | {"is_txn": bool(d.get("is_txn"))}


def write_artifacts(model_dir: Path) -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    vocab = load_vocab(model_dir / "tokenizer" / "tokenizer.json")
    write_vocab_txt(vocab, RESOURCES / "vocab.txt")
    (RESOURCES / "chartable.json").write_text(json.dumps(build_table(), ensure_ascii=False, separators=(",", ":")))
    meta = json.loads((model_dir / "meta.json").read_text())
    (RESOURCES / "extractor.json").write_text(json.dumps({
        "version": model_dir.name, "max_len": meta["max_len"], "tags": list(TAGS),
        "seq_classes": list(SEQ_CLASSES), "char_map": {"₹": "$", "•": "*"},
        "special": {"[PAD]": 0, "[UNK]": vocab["[UNK]"], "[CLS]": vocab["[CLS]"], "[SEP]": vocab["[SEP]"]},
    }, ensure_ascii=False, indent=2) + "\n")
    target = RESOURCES / "Extractor.mlmodelc"
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(model_dir / "Extractor.mlmodelc", target)
    FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)
    shutil.copy(model_dir / "extractor.int8.onnx", FLUTTER_ASSETS / "extractor.int8.onnx")


def tokenizer_fixture(texts: list[str], vocab, table, max_len: int) -> dict:
    cases = []
    for t in texts:
        enc = encode(prepare(t), vocab, table, max_len)
        cases.append({"text": t, "ids": enc.ids, "offsets": [list(o) for o in enc.offsets]})
    return {"max_len": max_len, "cases": cases}


def normalize_fixture() -> dict:
    amounts = ["450", "450.5", "1,23,456.78", "1,234.00", "30000.00", "500/-", "12,34", "4.567", "", "0.00",
               "313,938.00", "1,414,820.89", "9,025.00", "1,18,502.00", "07"]
    refs = ["626523840940", "hdfcn52026092212", "HDFCR520260922123456789", "12345", "IDFB6220M8743447",
            "HDFCN52026092212345678", "INFURNIATECHNOLOG", "HDFC7020902210002459", "N244243236394874",
            "62652384094", "6265238409401", "AB12345678901234"]
    tails = ["XX8816", "XXXXXXX8816", "XXXXX308816", "XXXXXXXX816", "*3293", "3293", "XX12", "xx3293",
             "XXXX XXXX XXXX 1234", "0787"]
    dates = ["22-Sep-26", "22SEP26", "22/09/2026", "2026-09-22", "SEP 22, 2026", "31-02-26", "31st Oct' 2024",
             "14-08", "29/02", "1450", "22.09.26", "22 Sep 2026", "22-September-2026", "1-9-26", "29-02-24",
             "29-02-25", "22-09/26", "1st Jan", "Sep 22", "22Sep", "25-SEP-26", "04/10/26", "69-01-01",
             "01-01-68", "22-SEPTEMBER-2026", "22 september 2026", "Sept 22, 2026", ""]
    names = ["Mr MO ALAM", "MO ALAM", "Dr. Priya Nair", "Mrinal Sen", "  SWIGGY  INSTAMART PRIVATE ",
             "M/s Balaji Stores.", "SHRI GANESH KIRANA", "smt. lakshmi", "-NETFLIX COM-", ""]
    edges = []
    for text, s, e in [("UMRN: HDFC7020902210002459 Ref 626523840940", 31, 43),
                       ("UMRN: HDFC7020902210002459 Ref 626523840940", 14, 26),
                       ("UMRN: HDFC7020902210002459 Ref 626523840940", 10, 26),
                       ("UMRN: HDFC7020902210002459 Ref 626523840940", 7, 10),
                       ("INR 3,13,938.00 credited", 4, 15), ("INR 3,13,938.00 credited", 13, 15),
                       ("INR 3,13,938.00 credited", 4, 8), ("PAN XXXXXX984D, A/c XX8816", 4, 13),
                       ("PAN XXXXXX984D, A/c XX8816", 20, 26), ("INR450 debited", 3, 6), ("₹450 paid", 1, 4)]:
        edges.append([text, s, e, clean_edges(text, s, e)])
    return {
        "amount_paise": [[a, normalize.amount_paise(a)] for a in amounts],
        "ref": [[r, normalize.ref(r)] for r in refs],
        "acct_tail": [[t, normalize.acct_tail(t)] for t in tails],
        "date_iso": [[d, normalize.date_iso(d)] for d in dates],
        "name": [[n, normalize.name(n)] for n in names],
        "clean_edges": edges,
    }


def _synthetic_logits(n_tokens: int, tags: list[str], seq: str) -> tuple[np.ndarray, np.ndarray]:
    t = np.full((n_tokens, len(TAGS)), -4.0)
    for i, tag in enumerate(tags):
        t[i, TAGS.index(tag)] = 4.0
    s = np.full(len(SEQ_CLASSES), -4.0)
    s[SEQ_CLASSES.index(seq)] = 4.0
    return t, s


def decode_fixture(texts: list[str], backend, vocab, table, max_len: int) -> dict:
    cases = []
    for t in texts:
        offsets, tag_logits, seq_logits = backend([t])
        n = len(encode(prepare(t), vocab, table, max_len).ids)
        tl = np.round(tag_logits[0][:n].astype(np.float64), 2)
        sl = np.round(seq_logits[0].astype(np.float64), 2)
        off = [list(o) for o in offsets[0][:n]]
        cases.append({"text": t, "offsets": off, "tag_logits": tl.tolist(), "seq_logits": sl.tolist(),
                      "expected": _fields(decode(t, off, tl, sl))})
    # Hand-built logits for branches real outputs rarely hit.
    t = "Rs.1,234.50 debited from a/c XX1234 Ref 626523840940"
    off = [[0, 0], [0, 2], [2, 3], [3, 4], [4, 5], [5, 8], [8, 9], [9, 11], [12, 19], [20, 24], [25, 28],
           [29, 31], [31, 35], [36, 39], [40, 52], [0, 0]]
    gold = ["O", "O", "O", "B-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "O", "O", "O",
            "B-OWN_ACCT", "I-OWN_ACCT", "O", "B-REF", "O"]
    crafted = [
        (gold, "debit"),
        (gold, "none"),                                                             # not a transaction
        (["O", "B-AMOUNT", "I-AMOUNT"] + ["O"] * 13, "debit"),                    # "Rs." -> no amount -> not admitted
        (["O", "O", "O", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT"] + ["O"] * 8, "credit"),
        (["O", "O", "O", "O", "O", "B-AMOUNT", "I-AMOUNT", "I-AMOUNT"] + gold[8:], "debit"),  # "234.50": edge cut
    ]
    for tags, seq in crafted:
        tl, sl = _synthetic_logits(len(off), tags, seq)
        cases.append({"text": t, "offsets": off, "tag_logits": tl.tolist(), "seq_logits": sl.tolist(),
                      "expected": _fields(decode(t, off, tl, sl))})
    return {"tags": list(TAGS), "seq_classes": list(SEQ_CLASSES), "cases": cases}


def model_fixture(texts: list[str], backend) -> dict:
    """End to end through Core ML. Only confident predictions: two runtimes'
    float noise may flip a borderline call, never a confident one."""
    cases = []
    offsets, tags, seqs = backend(texts)
    for i, t in enumerate(texts):
        p = decode(t, offsets[i], tags[i], seqs[i])
        if min(p["conf"].values()) >= 0.95:
            cases.append({"text": t, "expected": _fields(p)})
    return {"cases": cases}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", type=Path, required=True)
    args = ap.parse_args()

    _, tok, meta = load(args.model)
    max_len = meta["max_len"]
    vocab, table = load_vocab(args.model / "tokenizer" / "tokenizer.json"), Table(build_table())
    write_artifacts(args.model)
    FIXTURES.mkdir(parents=True, exist_ok=True)

    def dump(name: str, obj: dict) -> None:
        (FIXTURES / name).write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(f"{name}: {len(obj.get('cases', obj))} cases, {(FIXTURES / name).stat().st_size // 1024} KB")

    dump("extractor-tokenizer.json", tokenizer_fixture(EDGE_CASES + _texts(240, 1), vocab, table, max_len))
    dump("extractor-normalize.json", normalize_fixture())
    onnx = OnnxBackend(args.model / "extractor.int8.onnx", tok, max_len)
    dump("extractor-decode.json", decode_fixture(_texts(40, 2), onnx, vocab, table, max_len))
    coreml = CoreMLBackend(args.model / "Extractor.mlpackage", tok, max_len)
    dump("extractor-model.json", model_fixture(_texts(120, 3), coreml))


if __name__ == "__main__":
    main()
