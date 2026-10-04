# hisab-ml

Training data and evaluation for Hisab's on-device alert extractor: a small
**extractive** model that tags spans (amount, reference, payee, VPA, own and
counterparty account, date, balance) in bank/UPI SMS, app notifications and
emails. Every value it returns is a substring of the alert, so it can miss a
field but cannot invent one. The app's verifier then decides whether an alert
becomes a ledger entry (verbatim rail reference), a memo, or nothing.

Fully offline: nothing here or in the app sends alert text anywhere.

## Layout

| Path | What |
|---|---|
| `src/hisab_ml/templates.py` | Alert formats as templates (`{slot:LABEL}`, `[[a\|b]]`) |
| `src/hisab_ml/values.py` | Random surface forms: amounts, masks, refs, VPAs, names |
| `src/hisab_ml/normalize.py` | Span text → field value; the rules the app verifier ports |
| `src/hisab_ml/generate.py` | Renders records, writes template-held-out splits |
| `src/hisab_ml/evaluate.py` | Per-field scoring: correct / missing / wrong / spurious |
| `bench/baseline_regex.py` | Scores the shipped regex `AlertParser` (Dart port) |

## Commands

```bash
uv run pytest -q
uv run python -m hisab_ml.generate --out data/synthetic --seed 7
uv run python bench/baseline_regex.py data/synthetic/test.jsonl
uv run python -m hisab_ml.evaluate --gold data/synthetic/test.jsonl --pred <preds.jsonl>
```

`data/` is git-ignored: synthetic splits regenerate from the seed, and real
alerts (`data/real/`) are private and must never be committed.

## Splits

Whole templates are held out of training (stratified by channel and
debit/credit/non-transaction), so `test.jsonl` measures generalisation to
layouts the model has never seen. `val.jsonl` holds out samples of the training
templates. The private real-alert set is the final judge.

## Baseline: regex AlertParser, seed 7

`uv run python bench/baseline_regex.py data/synthetic/test.jsonl` (3,400 records,
17 unseen templates):

- is_txn recall 0.616, precision 0.999, false capture 0.0013
- core exact (direction + amount + own account + ref) 0.078 — it never extracts
  a reference, by design of the memo-only capture path
- date wrong 4.2%: ISO dates (`2026-05-17`) are read through their `26-05-17`
  substring as dd-mm-yy, a real bug in the shipped parser
