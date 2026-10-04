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

## Model

ELECTRA-small (14M parameters) with a BIO tag head over tokens and a
none/debit/credit head. `decode` admits a value only if it is a whole word or
number (never a slice of a longer one) and passes its strict normalizer, and it
admits an alert only if it has a readable amount. Shipped as
`extractor.int8.onnx`, 14.0 MB.

```bash
uv run python -m hisab_ml.generate --out data/synthetic-v4 --seed 7 --compose 25000
uv run python -m hisab_ml.realdata build      # labelled real alerts -> real-train / real-test
uv run python -m hisab_ml.train --data data/synthetic-v4 --out data/models/v4 \
    --extra data/real/real-train.jsonl:5 --eval data/real/real-test.jsonl
uv run python -m hisab_ml.export --model data/models/v4 --gold data/real/real-test.jsonl
```

### Results on real-test

The test set is 1,192 of the maintainer's real alerts in 305 formats. It is
split by format, so none of these layouts appear in training.

| | regex parser | v3 (synthetic only) | v4 (+ real-train) | v4 int8 |
|---|---|---|---|---|
| transactions detected | 0.505 | 0.983 | 0.917 | 0.953 |
| precision | 0.993 | 0.896 | 0.992 | 0.992 |
| non-transactions captured | 0.003 | 0.090 | 0.006 | 0.006 |
| fully correct (direction + amount + own account + ref) | 0.080 | 0.973 | 0.917 | 0.951 |
| wrong direction, amount or ref | 0 | 0 | 0 | 0 |

The v3 column already uses the no-amount admission rule; without it, v3
captured 27.5% of non-transactions.

### What did not work, and what fixed it

- **Hand templates alone:** v1 and v2 learned template identity. v2 read
  "mandate" as a non-transaction. The fix is `compose.py`: clauses assembled at
  random, so verbs and status words carry the meaning.
- **Trusting verbatim digits:** v1 tagged the last 12 digits of a 20-character
  mandate ID as a UPI reference. The fix is the edge rules in `decode`.
- **Strict reference and date shapes:** real UTRs carry letters
  (`IDFB6220M8743447`) or no bank code (`N244…`), and HDFC writes dates with
  no year (`14-08`). The labellers found these, and the normalizers now accept
  them.
- **Still open:** int8 differs from fp32 on borderline class calls; on
  real-test it happened to gain 3.6 points of detection. v4 also misses formats
  that real-train lacks, such as IDFC's "Monthly interest … earned … credited",
  because real-train's "earn X% interest" promos taught it the opposite. More
  real formats fix this, not more templates.

## Baseline: regex AlertParser, seed 7

`uv run python bench/baseline_regex.py data/synthetic/test.jsonl` (3,400 records,
17 unseen templates):

- is_txn recall 0.616, precision 0.999, false capture 0.0013
- core exact (direction + amount + own account + ref) 0.078 — it never extracts
  a reference, by design of the memo-only capture path
- date wrong 4.2%: ISO dates (`2026-05-17`) are read through their `26-05-17`
  substring as dd-mm-yy, a real bug in the shipped parser
