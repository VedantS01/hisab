"""Fine-tune the extractor.

    uv run python -m hisab_ml.train --data data/synthetic --out data/models/v1 --threads 2

Model selection uses `val` only (seen templates). `test` (unseen templates) is
scored once, after training, so it stays an honest generalisation number.
"""

from __future__ import annotations

import argparse
import json
import random
import time
from pathlib import Path

import torch
from torch import nn

from . import model as model_io
from .evaluate import format_report, load_gold, score
from .features import IGNORE, encode, load_tokenizer
from .predict import TorchBackend, predict_texts


def _batches(items, size, rng):
    order = list(range(len(items)))
    rng.shuffle(order)
    for i in range(0, len(order), size):
        yield [items[j] for j in order[i:i + size]]


def _collate(batch, pad_id: int, device: str):
    width = max(len(e.input_ids) for e in batch)
    ids = torch.full((len(batch), width), pad_id, dtype=torch.long)
    mask = torch.zeros((len(batch), width), dtype=torch.long)
    tags = torch.full((len(batch), width), IGNORE, dtype=torch.long)
    for i, e in enumerate(batch):
        n = len(e.input_ids)
        ids[i, :n] = torch.tensor(e.input_ids)
        mask[i, :n] = 1
        tags[i, :n] = torch.tensor(e.tag_ids)
    seq = torch.tensor([e.seq_id for e in batch])
    return ids.to(device), mask.to(device), tags.to(device), seq.to(device)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=Path("data/synthetic"))
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--base", default="google/electra-small-discriminator")
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--max-len", type=int, default=192)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--threads", type=int, default=2, help="CPU threads; take the cpu-gate budget")
    ap.add_argument("--extra", action="append", default=[],
                    help="more training records as PATH[:REPEAT], e.g. data/real/real-train.jsonl:5")
    ap.add_argument("--eval", action="append", default=[], type=Path,
                    help="extra held-out gold files scored after training")
    args = ap.parse_args()

    torch.set_num_threads(args.threads)
    torch.manual_seed(args.seed)
    rng = random.Random(args.seed)
    device = "mps" if torch.backends.mps.is_available() else "cpu"

    tok = load_tokenizer(args.base)
    train_records = load_gold(args.data / "train.jsonl")
    for spec in args.extra:
        path, _, repeat = spec.partition(":")
        # Real records are few next to the synthetic ones; repeating them is
        # the simplest way to give them weight without a weighted loss.
        train_records += load_gold(Path(path)) * int(repeat or 1)
    val_records = load_gold(args.data / "val.jsonl")
    train = [encode(r, tok, args.max_len) for r in train_records]
    n_spans = sum(len(r.spans) for r in train_records)
    misaligned, truncated = sum(e.misaligned for e in train), sum(e.truncated for e in train)
    longest = max(len(e.input_ids) for e in train)
    print(f"train={len(train)} spans={n_spans} misaligned={misaligned} truncated={truncated} "
          f"longest={longest} tokens device={device}")

    model = model_io.new(args.base).to(device)
    steps = args.epochs * ((len(train) + args.batch - 1) // args.batch)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.01)
    warmup = int(0.06 * steps)
    sched = torch.optim.lr_scheduler.LambdaLR(
        opt, lambda s: min((s + 1) / max(warmup, 1), max(0.0, (steps - s) / max(steps - warmup, 1))))
    ce = nn.CrossEntropyLoss(ignore_index=IGNORE)

    step, t0 = 0, time.time()
    for epoch in range(args.epochs):
        model.train()
        running = 0.0
        for batch in _batches(train, args.batch, rng):
            ids, mask, tags, seq = _collate(batch, tok.pad_token_id, device)
            tag_logits, seq_logits = model(ids, mask)
            loss = ce(tag_logits.reshape(-1, tag_logits.shape[-1]), tags.reshape(-1)) + ce(seq_logits, seq)
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            sched.step()
            step += 1
            running += loss.item()
            if step % 200 == 0:
                print(f"epoch {epoch + 1} step {step}/{steps} loss {running / 200:.4f} {time.time() - t0:.0f}s",
                      flush=True)
                running = 0.0
        model.eval()
        preds = predict_texts(TorchBackend(model, tok, args.max_len, device), [r.text for r in val_records])
        s = score(val_records, {r.id: p for r, p in zip(val_records, preds)})
        print(f"epoch {epoch + 1} val core_exact={s['core_exact']} is_txn={s['is_txn']}", flush=True)

    model.to("cpu")
    meta = {"base": args.base, "max_len": args.max_len, "epochs": args.epochs, "lr": args.lr,
            "batch": args.batch, "seed": args.seed, "train_records": len(train),
            "misaligned_spans": misaligned, "train_seconds": round(time.time() - t0)}
    meta["extra"] = args.extra
    model_io.save(model, tok, args.out, meta)

    for gold in [args.data / "test.jsonl", *args.eval]:
        records = load_gold(gold)
        preds = predict_texts(TorchBackend(model, tok, args.max_len), [r.text for r in records])
        s = score(records, {r.id: p for r, p in zip(records, preds)})
        (args.out / f"score-{gold.stem}.json").write_text(json.dumps(s, indent=2) + "\n")
        print(f"HELD OUT {gold}\n" + format_report(s), flush=True)


if __name__ == "__main__":
    main()
