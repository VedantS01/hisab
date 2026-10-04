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
from .compose import compose
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
        case "fund":
            return rng.choice(values.FUNDS)
        case "amc":
            return rng.choice(values.AMCS)
        case "folio":
            return f"{rng.randint(10**6, 10**8)}/{rng.randint(10, 99)}"
        case "nav":
            return f"{rng.uniform(10, 900):.3f}"
        case "units":
            return f"{rng.uniform(1, 2000):.3f}"
        case "order":
            # Long digit runs that are NOT rail references.
            return rng.choice([str(rng.randint(10**14, 10**15 - 1)), f"OD{rng.randint(10**15, 10**16 - 1)}",
                               f"{rng.randint(100, 999)}-{rng.randint(10**6, 10**7 - 1)}-{rng.randint(10**6, 10**7 - 1)}"])
        case "points":
            return str(rng.randint(1, 2000))
        case "umn":
            return f"{rng.getrandbits(128):032x}@{rng.choice(values.HANDLES)}"
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
        vpa=normalize.lower(vpa) if vpa else None,
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


def split_templates(templates: list[Template], test_every: int = 4) -> set[str]:
    """Held-out template ids. Each template's own hash decides, so adding a
    template never moves an existing one between train and test."""
    return {t.id for t in templates
            if int(hashlib.sha1(f"split:{t.id}".encode()).hexdigest(), 16) % test_every == 0}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("data/synthetic"))
    ap.add_argument("--per-template", type=int, default=400)
    ap.add_argument("--test-per-template", type=int, default=200)
    ap.add_argument("--val-fraction", type=float, default=0.1)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--compose", type=int, default=0, help="compositional records added to train/val")
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

    # Compositional records train the model to read clauses rather than
    # recognise templates. Never in test: the held-out hand templates are.
    for i in range(args.compose):
        r = make_record(compose(rng), i, rng)
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
