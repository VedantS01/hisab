"""Hand annotations -> records, for the private real-alert test set.

    uv run python -m hisab_ml.label data/real/annotations.json data/real/real.jsonl

Annotation file: a JSON list of
    {"text": "...", "kind": "debit|credit|none", "channel": "sms",
     "labels": {"AMOUNT": "239.00", "REF": "627775786529", ...}, "note": "..."}
Each label value is a substring of the text; its first occurrence becomes the
span. Real alerts are personal financial data: keep them under data/ (ignored).
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from .generate import fields_from_spans
from .predict import clean_edges
from .schema import LABELS, Record, Span
from .templates import Template


def _find(text: str, value, label: str) -> int:
    """A label value is a substring (first occurrence) or [substring, n] for
    its n-th occurrence, 1-based."""
    sub, n = (value, 1) if isinstance(value, str) else (value[0], int(value[1]))
    start = -1
    for _ in range(n):
        start = text.find(sub, start + 1)
        assert start >= 0, f"{label}={value!r} not found in text"
    return start


def to_record(a: dict) -> Record:
    text, kind = a["text"], a["kind"]
    assert kind in ("debit", "credit", "none"), f"kind={kind!r}"
    spans = []
    for label, value in a.get("labels", {}).items():
        assert label in LABELS, f"unknown label {label}"
        start = _find(text, value, label)
        sub = value if isinstance(value, str) else value[0]
        assert sub == sub.strip() and sub, f"{label}={value!r} has edge whitespace or is empty"
        assert clean_edges(text, start, start + len(sub)), f"{label}={value!r} cuts through a longer number or word"
        spans.append(Span(start, start + len(sub), label))
    spans.sort(key=lambda s: s.start)
    is_txn = kind in ("debit", "credit")
    assert is_txn or not spans, "non-transactions carry no spans"
    t = Template(id="real", channel=a.get("channel", "sms"), is_txn=is_txn,
                 direction=kind if is_txn else None, text="")
    fields = fields_from_spans(text, spans, t)
    for label, value in a.get("labels", {}).items():
        assert label == "PAYEE" or label == "VPA" or getattr(fields, {
            "AMOUNT": "amount_paise", "BALANCE": "balance_paise", "REF": "ref", "OWN_ACCT": "own_acct_tail",
            "CPTY_ACCT": "cpty_acct_tail", "DATE": "date_iso"}[label]) is not None, f"{label}={value!r} does not normalize"
    rid = "real-" + hashlib.sha1(text.encode()).hexdigest()[:10]
    return Record(id=rid, text=text, spans=spans, fields=fields, channel=t.channel,
                  template_id="real", issuer=a.get("issuer", "unknown"), meta={"note": a.get("note", "")})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("annotations", type=Path)
    ap.add_argument("out", type=Path)
    args = ap.parse_args()
    records = [to_record(a) for a in json.loads(args.annotations.read_text())]
    # Identical alerts (the same SMS twice) collapse to one id; keep each copy.
    seen: dict[str, int] = {}
    for r in records:
        seen[r.id] = seen.get(r.id, 0) + 1
        if seen[r.id] > 1:
            r.id += f"-{seen[r.id]}"
    args.out.write_text("".join(json.dumps(r.to_json(), ensure_ascii=False) + "\n" for r in records))
    kinds = [r.fields.direction or "none" for r in records]
    print(f"{len(records)} records: " + ", ".join(f"{k}={kinds.count(k)}" for k in sorted(set(kinds))))


if __name__ == "__main__":
    main()
