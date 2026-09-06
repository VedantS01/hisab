# Contributing to Hisab

The most valuable contribution is a **parser for a statement format Hisab
doesn't read yet** — another bank, another UPI app, or another export
format of an existing source. Nine parsers exist; every one followed the
recipe below.

## Ground rules

- **Never commit a real statement.** Not yours, not redacted-ish. Tests
  run on *synthetic fixtures* that mirror a format's structure with fake
  data. Real files live in the gitignored `samples/` on your machine only.
- **Deterministic or loud.** A parser either extracts a row exactly or
  throws `ParseError.malformedRow` — no silent guessing. Where the format
  offers redundancy (a running balance, printed totals), verify against
  it and throw on mismatch, so a misparse can never miscount money.
- No third-party dependencies. `HisabCore` is Foundation + system
  frameworks; it already contains dependency-free readers for zip/XLSX,
  legacy CDF/BIFF8 XLS, and PDFKit-based text/geometry extraction —
  reuse them.
- Money is integer paise (`Int64`). Dates resolve in IST
  (`YearMonth.istCalendar`).

## The parser recipe

1. **Map the format.** Dump your file's raw structure (for PDFs,
   `swift tools/dump-pdf.swift <file> [password]` shows exactly what
   PDFKit's text layer sees). Identify: where the statement period lives,
   how a transaction row starts and ends, where the reference ID,
   amount, and direction come from.
2. **Build a synthetic fixture** that mirrors that structure —
   fake names, fake amounts, same shape (see
   `HisabCore/Tests/HisabCoreTests/` for text fixtures and
   `Fixtures/` for generated binary ones).
3. **Write failing tests first** against the fixture: row count,
   directions, amounts in paise, references, declared period, and at
   least one malformed-input case that must throw.
4. **Implement** a `StatementParser`: `canParse(data:filename:)` must
   deterministically recognize the format (content sniffing preferred,
   filename as fallback for password-locked files), and
   `parse(data:password:)` returns a `ParsedDocument`.
5. **Validate against your real file locally** — transaction count and
   debit/credit sums must match the statement's own printed totals
   exactly. Put the numbers in your PR description; the file itself
   never leaves your machine.
6. **Register it.** A new *format* for an existing source: append the
   parser in `ParserRegistry.live`. A new *source* additionally needs:
   a `Source` enum case (display name + `.paymentApp`/`.bank` kind),
   a glyph in `HisabTheme.sourceGlyph`, and short names in
   `CoverageStrip`/`BucketsView`. The grid, chips, and analytics adapt
   automatically.

## Identity & dedup (important for correctness)

Within a source, a transaction's identity is its **reference ID +
direction** (a refund reuses the ref with the opposite direction). Rows
without a rail reference need a deterministic fallback: bank statements
use a synthetic key from date + amount + resulting balance (see
`IDFCStatementText.syntheticReference`) so the same row dedups across
different renditions (PDF vs XLSX vs TXT) of the same statement. If your
format has ref-less rows, pick the fallback that is stable across every
export format the source offers, and prove it with a cross-format test.

## Running checks

```sh
swift test --package-path HisabCore   # core suite (runs on macOS, fast)
make gen && make build                # app builds for the simulator
```

CI runs both on every PR.
