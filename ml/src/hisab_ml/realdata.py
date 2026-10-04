"""Real-alert pipeline: batch the export, check labels, build format-split records.

    uv run python -m hisab_ml.realdata batch                 # messages_raw.jsonl -> batches/batch-NN.jsonl
    uv run python -m hisab_ml.realdata check labels/batch-07.json
    uv run python -m hisab_ml.realdata build                 # -> real-train.jsonl, real-test.jsonl

Everything lives under data/real/ (git-ignored). Labels name the message by id
and give only kind + substrings; the text always comes from the batch, so a
labeller cannot mistype it. The split is by FORMAT (sender + text skeleton),
so real-test measures layouts the model never trained on.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

from .label import to_record

REAL = Path("data/real")
BATCH = 100


def sender_key(s: str) -> str:
    s = (s or "").upper()
    s = re.sub(r"^[A-Z]{2}-", "", s)          # AX-HDFCBK -> HDFCBK
    s = re.sub(r"\(.*\)$", "", s)             # HDFCBK-S(SMSFT_FI) -> HDFCBK-S
    return re.sub(r"-[A-Z]$", "", s)          # HDFCBK-S -> HDFCBK


def skeleton(text: str) -> str:
    t = re.sub(r"\d+", "0", text)
    t = re.sub(r"\b[A-Z][A-Za-z]+\b", "W", t)
    return " ".join(t.lower().split()[:8])


def format_key(sender: str, text: str) -> str:
    return f"{sender_key(sender)}|{skeleton(text)}"


def split_of(key: str) -> str:
    return "test" if int(hashlib.sha1(f"real:{key}".encode()).hexdigest(), 16) % 2 == 0 else "train"


def batch() -> None:
    msgs = [json.loads(l) for l in (REAL / "messages_raw.jsonl").read_text().splitlines() if l.strip()]
    out = REAL / "batches"
    out.mkdir(parents=True, exist_ok=True)
    for b in range(0, len(msgs), BATCH):
        rows = [{"id": f"m{i:05d}", "sender": m.get("sender", ""), "text": m["text"]}
                for i, m in enumerate(msgs[b:b + BATCH], start=b)]
        (out / f"batch-{b // BATCH:02d}.jsonl").write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    print(f"{len(msgs)} messages -> {(len(msgs) + BATCH - 1) // BATCH} batches in {out}")


def _messages() -> dict[str, dict]:
    out = {}
    for p in sorted((REAL / "batches").glob("batch-*.jsonl")):
        for line in p.read_text().splitlines():
            if line.strip():
                m = json.loads(line)
                out[m["id"]] = m
    return out


def _records(labels_path: Path, msgs: dict[str, dict]):
    """(records, errors) for one labels file."""
    records, errors = [], []
    for a in json.loads(labels_path.read_text()):
        m = msgs.get(a.get("id"))
        if m is None:
            errors.append(f"{a.get('id')}: unknown id")
            continue
        try:
            r = to_record({**a, "text": m["text"], "issuer": sender_key(m["sender"])})
        except AssertionError as e:
            errors.append(f"{a['id']}: {e}")
            continue
        r.id = m["id"]
        r.template_id = format_key(m["sender"], m["text"])
        r.meta = {"sender": m["sender"], "note": a.get("note", ""), "uncertain": bool(a.get("uncertain"))}
        records.append(r)
    return records, errors


def check(path: Path) -> int:
    msgs = _messages()
    batch_ids = {json.loads(l)["id"] for l in (REAL / "batches" / f"{path.stem}.jsonl").read_text().splitlines()
                 if l.strip()} if (REAL / "batches" / f"{path.stem}.jsonl").exists() else set()
    records, errors = _records(path, msgs)
    labelled = {r.id for r in records} | {e.split(":")[0] for e in errors}
    missing = sorted(batch_ids - labelled)
    for e in errors:
        print("ERROR", e)
    if missing:
        print("MISSING", ", ".join(missing))
    kinds = Counter(r.fields.direction or "none" for r in records)
    print(f"{path.name}: {len(records)} ok, {len(errors)} errors, {len(missing)} missing  {dict(kinds)}")
    return 1 if errors or missing else 0


def build() -> None:
    msgs = _messages()
    records, errors = [], []
    for p in sorted((REAL / "labels").glob("batch-*.json")):
        r, e = _records(p, msgs)
        records += r
        errors += e
    splits: dict[str, list] = {"train": [], "test": []}
    for r in records:
        splits[split_of(r.template_id)].append(r)
    for name, rs in splits.items():
        (REAL / f"real-{name}.jsonl").write_text(
            "".join(json.dumps(r.to_json(), ensure_ascii=False) + "\n" for r in rs))
    formats = {name: len({r.template_id for r in rs}) for name, rs in splits.items()}
    print(f"labelled={len(records)} of {len(msgs)} errors={len(errors)} "
          f"train={len(splits['train'])} test={len(splits['test'])} formats={formats}")
    for name, rs in splits.items():
        print(f"  {name}: {dict(Counter(r.fields.direction or 'none' for r in rs))}, "
              f"uncertain={sum(r.meta['uncertain'] for r in rs)}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["batch", "check", "build"])
    ap.add_argument("path", nargs="?", type=Path)
    args = ap.parse_args()
    if args.cmd == "batch":
        batch()
    elif args.cmd == "check":
        sys.exit(check(args.path))
    else:
        build()


if __name__ == "__main__":
    main()
