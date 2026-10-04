"""Score predicted fields against gold records.

    uv run python -m hisab_ml.evaluate --gold data/synthetic/test.jsonl --pred preds.jsonl

Predictions are JSONL `{"id": ..., "fields": {...}}` using the `Fields` keys;
missing keys count as None. Per field, every gold transaction lands in exactly
one bucket:

  correct   prediction equals gold (both None included)
  missing   gold has a value, prediction is None   -> falls back to a memo; safe
  wrong     both present and different             -> a bad ledger row; the
                                                      error class that matters
  spurious  gold is None, prediction has a value   -> also a bad ledger row
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

from . import normalize
from .schema import Record

FIELDS = ("direction", "amount_paise", "ref", "own_acct_tail", "cpty_acct_tail", "date_iso",
          "balance_paise", "counterparty")
CORE = ("direction", "amount_paise", "own_acct_tail", "ref")


def _counterparty(f: dict) -> set[str]:
    out = set()
    if f.get("payee"):
        out.add(normalize.name(f["payee"]))
    if f.get("vpa"):
        out.add(f["vpa"].lower())
    return out


def _bucket(gold, pred) -> str:
    if gold == pred:
        return "correct"
    if pred is None:
        return "missing"
    if gold is None:
        return "spurious"
    return "wrong"


def score(gold: list[Record], preds: dict[str, dict]) -> dict:
    txn = {"tp": 0, "fp": 0, "fn": 0, "tn": 0}
    buckets: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    core_exact = n_txn = 0
    by_channel: dict[str, list[int]] = defaultdict(lambda: [0, 0])

    for r in gold:
        p = preds.get(r.id, {})
        g = r.fields.__dict__
        p_txn = bool(p.get("is_txn"))
        key = ("tp" if p_txn else "fn") if r.fields.is_txn else ("fp" if p_txn else "tn")
        txn[key] += 1
        if not r.fields.is_txn:
            continue
        n_txn += 1
        p = p if p_txn else {}
        ok_all = True
        for f in FIELDS:
            if f == "counterparty":
                gc, pc = _counterparty(g), _counterparty(p)
                b = "correct" if gc == pc or gc & pc else _bucket(gc or None, pc or None)
            else:
                b = _bucket(g.get(f), p.get(f))
            buckets[f][b] += 1
            # How often gold HAS a value: "correct" includes None == None, so
            # a predictor that never emits a field still scores its absence.
            buckets[f]["present"] += bool(gc) if f == "counterparty" else g.get(f) is not None
            if f in CORE and b != "correct":
                ok_all = False
        core_exact += ok_all
        by_channel[r.channel][0] += ok_all
        by_channel[r.channel][1] += 1

    def ratio(a, b):
        return round(a / b, 4) if b else None

    return {
        "n": len(gold),
        "n_txn": n_txn,
        "is_txn": {
            "precision": ratio(txn["tp"], txn["tp"] + txn["fp"]),
            "recall": ratio(txn["tp"], txn["tp"] + txn["fn"]),
            "false_capture_rate": ratio(txn["fp"], txn["fp"] + txn["tn"]),
        },
        "core_exact": ratio(core_exact, n_txn),
        "core_exact_by_channel": {c: ratio(a, b) for c, (a, b) in sorted(by_channel.items())},
        "fields": {f: {b: ratio(c, n_txn) for b, c in sorted(buckets[f].items())} for f in FIELDS},
    }


def load_gold(path: Path) -> list[Record]:
    return [Record.from_json(json.loads(line)) for line in path.read_text().splitlines() if line.strip()]


def load_preds(path: Path) -> dict[str, dict]:
    out = {}
    for line in path.read_text().splitlines():
        if line.strip():
            d = json.loads(line)
            out[d["id"]] = d["fields"]
    return out


def format_report(s: dict) -> str:
    lines = [f"n={s['n']} txn={s['n_txn']}  is_txn {s['is_txn']}",
             f"core_exact (direction+amount+own_acct+ref) = {s['core_exact']}  {s['core_exact_by_channel']}",
             f"{'field':16} {'present':>8} {'correct':>8} {'missing':>8} {'wrong':>8} {'spurious':>8}"]
    for f, b in s["fields"].items():
        lines.append(f"{f:16} " + " ".join(f"{(b.get(k) or 0):8.3f}" for k in
                                           ("present", "correct", "missing", "wrong", "spurious")))
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gold", type=Path, required=True)
    ap.add_argument("--pred", type=Path, required=True)
    ap.add_argument("--json", type=Path, help="also write the full score as JSON")
    args = ap.parse_args()
    s = score(load_gold(args.gold), load_preds(args.pred))
    print(format_report(s))
    if args.json:
        args.json.write_text(json.dumps(s, indent=2) + "\n")


if __name__ == "__main__":
    main()
