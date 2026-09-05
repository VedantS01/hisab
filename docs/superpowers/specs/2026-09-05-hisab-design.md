# Hisab — design spec

*2026-09-05 · approved direction from brainstorming session*

## What it is

**Hisab** (हिसाब — "the accounts") is a private, on-device iOS app for
Vedant's personal expense analysis. He periodically exports transaction
statements from Google Pay, Paytm, HDFC bank, and IDFC bank, imports the
files into Hisab, and the app parses them deterministically, organizes
them into monthly time buckets, cross-checks payment-app records against
bank statements, and presents expense analytics on a dashboard.

Not a general-purpose product: parsers are written against *his* exact
export formats (samples in `samples/`, gitignored). No server, no
account, no network calls. Data lives in SwiftData on the phone.

## Decisions already made

- **Platform**: native iOS, SwiftUI + SwiftData. Xcode 26 / iOS 26 SDK,
  sensible deployment target (iOS 18+).
- **Distribution**: Vedant's paid Apple Developer account (device
  install / TestFlight). No App Store release planned.
- **Privacy**: on-device only. Imported files are copied into the app
  sandbox; nothing leaves the device.
- **Architecture**: two-part split —
  - `HisabCore`: a pure-Swift package (Foundation only) holding all
    domain logic: models, parser protocol + parsers, month-bucket
    derivation, dedup, reconciliation, analytics aggregation. Fully
    unit-tested with `swift test` on macOS.
  - `Hisab` app: thin SwiftUI/SwiftData shell over HisabCore.
- **Repo**: public GitHub repo `VedantS01/hisab`. `samples/` is
  gitignored — real financial files never leave the machine. Tests use
  committed *synthetic* fixtures that mirror the real formats.

## Domain model

- **SourceType**: `gpay | paytm | hdfc | idfc` — a registry, extensible
  (each entry knows its display name, kind `.paymentApp` or `.bank`,
  and its parser).
- **SourceDocument**: one imported file. Fields: source type, original
  filename, import date, sha256 of file bytes (rejects exact-duplicate
  imports), declared statement period (parsed from the file header when
  the format carries one, else min…max of its transaction dates),
  stored copy of the file in the app sandbox.
- **Transaction**: date, amount (integer paise — no floating point
  money), direction (debit/credit), counterparty/merchant string,
  reference IDs (UPI ref, bank ref when present), narration/raw text,
  link to its SourceDocument, category, and a **content hash**
  (source type + date + amount + direction + reference/narration) used
  for cross-document dedup.
- **CategoryRule**: ordered, user-editable substring/regex →
  category mappings, seeded with Indian-merchant defaults (Swiggy,
  Zomato, BigBasket, IRCTC, petrol pumps, …). Re-running rules is
  idempotent; manual category overrides on a transaction are sticky.
- **MatchLink**: reconciliation result joining one payment-app
  transaction to one bank transaction, with the tier that matched it.

## Month buckets

Buckets are **derived, not stored**. The bucket grid is computed from
the union of: every month covered by any document's declared period,
plus any months the user manually pinned as "awaiting". A document
covering 2025-04…2026-03 (a yearly statement) lights up all 12 buckets
in its column. Cell state per (month, source): **present** (≥1 document
covers it) or **awaiting**. Manual pinning lets a future or past month
appear before any file exists.

**Overlap rule**: monthly + yearly statements covering the same month
double-import the same transactions; the content hash dedups them, so
analytics never double-count. The newest document wins for the stored
raw row; the transaction keeps links discoverable via hash.

## Reconciliation

Runs per month whenever that month has at least one payment-app-side
document and one bank-side document. Tiered matching of app-side
transactions against bank-side ones:

1. **Tier 1 — reference**: exact UPI/bank reference ID match.
2. **Tier 2 — amount + date window**: same amount and direction within
   ±2 days, greedily matched closest-date-first, each bank transaction
   used at most once.

Outcomes: bank transaction → *matched* or *bank-only* (spending outside
the payment apps: cards, NACH, cash withdrawals); app transaction →
*matched* or *unmatched* (a flag worth investigating). The
reconciliation screen shows the three lists per month with counts.

## Analytics

Computed values (in HisabCore, pure functions over transactions):
monthly spend/income/net, month-over-month deltas, 6-month trend,
category breakdown, top merchants, per-source subtotals. **Source of
truth per month**: deduped bank-side transactions where a bank document
is present; payment-app data fills months that have no bank coverage
(the dashboard labels which basis a month uses).

## App screens

1. **Dashboard** (home) — designed by Claude, full creative ownership:
   - Hero card: this month's total spend, ▲/▼ delta vs last month,
     income and net lines.
   - 6-month spend trend (bar chart, current month highlighted).
   - Coverage strip: four source chips for the selected month
     (present/awaiting at a glance) → taps through to the grid.
   - Reconciliation health: matched %, count of unmatched app-side
     transactions as an attention badge.
   - Category breakdown: top-5 horizontal bars + "other".
   - Top merchants (top 5 by spend).
   - Recent transactions (last 10, with source glyphs).
2. **Coverage grid** — rows = months (newest first), columns = the four
   sources; cells present/awaiting; pull to pin a new month; tapping a
   present cell lists that cell's documents.
3. **Import** — Files-app picker; auto-detects source type from
   content (user can override); password prompt for locked PDFs
   (per-source password remembered in Keychain); import report
   (N transactions, M new after dedup, months touched).
4. **Transactions** — filterable list (month, source, category,
   unmatched-only); tap to edit category.
5. **Reconciliation** — per-month matched / bank-only / unmatched
   lists.
6. **Settings** — category rules editor, pinned months, data reset.

## Branding — "bahi-khata" design language

The visual identity draws from the traditional Indian **bahi-khata**:
the red-cloth-bound ledger.

- **Palette**: Khata Red `#A4243B` (brand/primary, debits), Roshnai Ink
  `#22333B` (text), Kagaz Cream `#F5EFE6` (light background), Sona Gold
  `#D9A441` (accents/highlights), Hara Green `#3A7D44` (credits).
  Dark mode: ink-derived dark background, cream text, same red/gold.
- **Typography**: system SF Pro; all money in monospaced digits;
  amounts formatted Indian-style (₹1,23,456.78).
- **App icon**: a front-facing bahi ledger — khata-red field, cream
  page with ink ledger lines and a gold binding thread, generated
  programmatically (CoreGraphics script → 1024px PNG) and committed.
- Reusable SwiftUI theme file (`HisabTheme`) so every screen pulls
  from the same tokens.

## Testing

- HisabCore: TDD, `swift test` on macOS. Synthetic fixture files per
  format (built to byte-match the real samples' structure) committed
  under `Tests/Fixtures/`.
- Parsers are written only once real samples exist in `samples/`;
  each parser gets fixtures covering: normal rows, edge rows (refunds,
  failed transactions, reversals), and period-header extraction.
- App layer: build-and-boot check in the iOS simulator; UI kept thin
  enough that core tests carry the correctness burden.
- CPU discipline: builds/tests run through `~/.claude/scripts/cpu-gate.sh`.

## Build order

1. Repo + CI-less scaffold: HisabCore package, theme, icon, spec.
2. HisabCore domain: models, bucket derivation, dedup, reconciliation,
   analytics — TDD.
3. Parsers (blocked on samples arriving in `samples/`).
4. App shell: dashboard, grid, import flow, transactions list.
5. Reconciliation + settings screens.
6. Device install via paid dev account; iterate on real data.

## Out of scope (YAGNI)

Budgets/alerts, share-sheet extension (later), iCloud sync, multi-user,
export/reports, widgets, automatic bank fetch (AA framework), any
server component.
