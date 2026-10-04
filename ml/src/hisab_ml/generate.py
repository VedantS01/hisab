"""Render templates into labelled records and write template-held-out splits.

    uv run python -m hisab_ml.generate --out data/synthetic --per-template 400 --seed 7
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
from collections import Counter
from pathlib import Path

from . import normalize, values
from .schema import LABELS, Fields, Record, Span
from .templates import TEMPLATES, Template

_CHOICE = re.compile(r"\[\[(.*?)\]\]", re.S)
_SLOT = re.compile(r"\{(\w+)(?::(\w+))?\}")

TOLLS = ["KHED SHIVAPUR TOLL PLAZA", "Atal Setu Toll", "NH48 Manesar Toll", "Electronic City Toll",
         "Kherki Daula Toll Plaza", "Paranur Toll Plaza", "Vashi Toll Naka", "Hosur Road Toll"]
EMPLOYER_SUFFIX = ["PVT LTD", "TECHNOLOGIES PVT LTD", "INDIA PRIVATE LIMITED", "SOLUTIONS LLP", "LTD"]


def _slot(name: str, rng: random.Random, ifsc: str, bank: str) -> str:
    match name:
        case "amt" | "bal" | "lim":
            return values.amount(rng)
        case "cur":
            return values.currency(rng)
        case "date":
            return values.date_text(rng)
        case "time":
            return values.time_text(rng)
        case "acct" | "loan":
            return values.acct(rng)
        case "card":
            return values.card(rng)
        case "tail":
            return "".join(rng.choice("0123456789") for _ in range(4))
        case "rrn":
            return values.rrn(rng)
        case "neft":
            return values.neft_utr(rng, ifsc)
        case "rtgs":
            return values.rtgs_utr(rng, ifsc)
        case "person":
            return values.person(rng)
        case "merchant":
            return values.merchant(rng)
        case "payee":
            return values.payee(rng)
        case "employer":
            return f"{rng.choice(values.LAST).upper()} {rng.choice(EMPLOYER_SUFFIX)}"
        case "toll":
            return rng.choice(TOLLS)
        case "vpa":
            return values.vpa(rng)
        case "helpline":
            return values.helpline(rng)
        case "otp":
            return values.otp(rng)
        case "user":
            return values.user_name(rng)
        case "bank":
            return bank
        case "atm":
            return f"{rng.choice(['S1', 'S1C', 'N', 'DCN'])}{rng.randint(10_000, 99_999)}"
        case "umrn":
            return f"{ifsc}{rng.randint(10**15, 10**16 - 1)}"
        case "chq":
            return f"{rng.randint(0, 999_999):06d}"
        case "vehicle":
            return f"{rng.choice(['MH12', 'KA05', 'DL3C', 'TN09', 'GJ01'])}{rng.choice('ABCDEFGH')}{rng.choice('JKLMNP')}{rng.randint(1000, 9999)}"
    raise KeyError(f"unknown slot {{{name}}}")


def render(t: Template, rng: random.Random) -> tuple[str, list[Span], str]:
    """Text and spans for one sample of a template, plus the issuer used."""
    bank = t.issuer or rng.choice(list(values.ISSUERS))
    ifsc = values.ISSUERS[bank]
    # Choices first, so slot offsets are computed on the final text.
    text = _CHOICE.sub(lambda m: rng.choice(m.group(1).split("|")), t.text)
    out, spans, pos = [], [], 0
    for m in _SLOT.finditer(text):
        out.append(text[pos:m.start()])
        filled = _slot(m.group(1), rng, ifsc, bank)
        start = sum(len(s) for s in out)
        out.append(filled)
        if m.group(2):
            spans.append(Span(start, start + len(filled), m.group(2)))
        pos = m.end()
    out.append(text[pos:])
    return "".join(out), spans, bank


def augment(text: str, rng: random.Random) -> str:
    """Length-preserving noise only, so spans stay valid."""
    if rng.random() < 0.15:
        text = text.replace("\n", " ")
    if rng.random() < 0.05 and len(text.upper()) == len(text):
        text = text.upper()
    return text


def fields_from_spans(text: str, spans: list[Span], t: Template) -> Fields:
    first: dict[str, str] = {}
    for s in spans:
        first.setdefault(s.label, text[s.start:s.end])
    vpa = first.get("VPA")
    return Fields(
        is_txn=t.is_txn,
        direction=t.direction,
        amount_paise=normalize.amount_paise(first["AMOUNT"]) if "AMOUNT" in first else None,
        ref=normalize.ref(first["REF"]) if "REF" in first else None,
        payee=normalize.name(first["PAYEE"]) if "PAYEE" in first else None,
        vpa=vpa.lower() if vpa else None,
        own_acct_tail=normalize.acct_tail(first["OWN_ACCT"]) if "OWN_ACCT" in first else None,
        cpty_acct_tail=normalize.acct_tail(first["CPTY_ACCT"]) if "CPTY_ACCT" in first else None,
        date_iso=normalize.date_iso(first["DATE"]) if "DATE" in first else None,
        balance_paise=normalize.amount_paise(first["BALANCE"]) if "BALANCE" in first else None,
    )


def make_record(t: Template, i: int, rng: random.Random) -> Record:
    text, spans, bank = render(t, rng)
    text = augment(text, rng)
    for s in spans:
        assert s.label in LABELS, s.label
    return Record(id=f"{t.id}-{i:05d}", text=text, spans=spans,
                  fields=fields_from_spans(text, spans, t),
                  channel=t.channel, template_id=t.id, issuer=bank)


def split_templates(templates: list[Template], test_every: int = 5) -> set[str]:
    """Held-out template ids, stratified by (channel, kind) so the test set
    contains unseen debits, credits and non-transactions on every channel
    that has enough formats to spare one."""
    groups: dict[tuple, list[Template]] = {}
    for t in templates:
        groups.setdefault((t.channel, t.direction or "none"), []).append(t)
    held: set[str] = set()
    for group in groups.values():
        if len(group) < 3:
            continue
        ranked = sorted(group, key=lambda t: hashlib.sha1(t.id.encode()).hexdigest())
        held.update(t.id for k, t in enumerate(ranked) if k % test_every == test_every // 2)
    return held


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("data/synthetic"))
    ap.add_argument("--per-template", type=int, default=400)
    ap.add_argument("--test-per-template", type=int, default=200)
    ap.add_argument("--val-fraction", type=float, default=0.1)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    held = split_templates(TEMPLATES)
    splits: dict[str, list[Record]] = {"train": [], "val": [], "test": []}
    for t in TEMPLATES:
        n = args.test_per_template if t.id in held else args.per_template
        for i in range(n):
            r = make_record(t, i, rng)
            if t.id in held:
                splits["test"].append(r)
            else:
                splits["val" if rng.random() < args.val_fraction else "train"].append(r)

    args.out.mkdir(parents=True, exist_ok=True)
    for name, records in splits.items():
        rng.shuffle(records)
        with (args.out / f"{name}.jsonl").open("w") as f:
            for r in records:
                f.write(json.dumps(r.to_json(), ensure_ascii=False) + "\n")
    manifest = {
        "seed": args.seed,
        "templates": len(TEMPLATES),
        "held_out_templates": sorted(held),
        "counts": {k: len(v) for k, v in splits.items()},
        "label_counts": dict(Counter(s.label for r in splits["train"] for s in r.spans)),
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({k: manifest[k] for k in ("templates", "counts")}), f"held_out={len(held)}")


if __name__ == "__main__":
    main()
