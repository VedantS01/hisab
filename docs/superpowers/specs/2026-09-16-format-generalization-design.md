# Format Generalization — Design (v2)

Date: 2026-09-16 · Status: approved in discussion, pending spec review
Owner: Vedant (decisions confirmed interactively; v2 supersedes the
same-day v1 after Vedant's simplification pass)

## Goal

Make Hisab useful beyond its author's own accounts: parse statements
from **any Indian bank**, keep UPI-app support growing (add
**PhonePe**), ship a **standard India-wide categorization ruleset**
with polite on-device rule suggestions — while *strengthening* the two
founding guarantees:

1. **Privacy**: the app makes **zero network requests, ever** — this
   design removes even the possibility, no exceptions to explain.
2. **Correctness**: nothing unvalidated ever enters the ledger; every
   bank parse must prove itself **to the paisa**.

Out of scope here (own later brainstorms): the Android/Google Play
port (which will port the *generalized* core produced by this work),
and any LLM-assisted parsing.

## Decisions (confirmed 2026-09-16, revised same day)

| Question | Decision |
|---|---|
| Order of the three workstreams | Formats → rulesets (rides along) → Android |
| Unknown-format UX | **Silent** generic engine: parses-and-proves or fails cleanly into an email-based "request this format" flow. **No mapping UI.** |
| UPI apps | Curated **code parsers** (few players, printed-totals validation); add PhonePe now |
| Spec/ruleset distribution | **Bundled only** — new formats and rules ship in app updates. No catalog fetch of any kind. |
| Engine architecture | Inference proposes, balance chain disposes, specs remember — with inference tuned **conservative** (ambiguity = unsupported, never a guess) |
| Format requests | In-app email (user-initiated share of a data-free format fingerprint); support lands in the next update |
| Rule suggestions | On-device suggestion engine; at most **one** prompt per app launch, gated on substantial + frequent spend |

## The universality claim, made honest

We market "works with any Indian bank statement." The claim rests on
the engine, not on enumerating banks:

- every Indian savings/current-account statement, whatever the
  container (PDF, XLSX, XLS, TXT, CSV), is the same table — date ·
  narration · reference · debit/credit · **running balance**;
- the balance column is a checksum over the whole statement: a
  candidate column mapping is accepted **only** if
  `prev ± amount == next` closes exactly, row by row, to the paisa.
  The engine therefore either parses *correctly* or refuses — it can
  never silently mis-parse;
- curated bundled specs make the major banks crisp and instant;
  generic inference catches unseen-but-well-formed formats; the
  request flow covers the rest via app updates.

## Architecture (HisabCore `GenericBank` module)

All pure Swift, TDD'd with synthetic fixtures, like the rest of
HisabCore.

- **`NormalizedTable`** — `[[Cell]]` plus per-row provenance. The five
  container readers (geometric PDF, MinimalZip/XLSX, MinimalXLS, TXT
  ruler-slicing, CSV) get a common output type instead of each feeding
  a bespoke parser.
- **`ColumnInference`** — proposes candidate role assignments
  (date / narration / reference / debit / credit / amount / balance)
  from content shape. **Conservative by design**: it succeeds only
  when exactly one candidate mapping closes the balance chain; two
  plausible mappings, or none, mean "unsupported", never a guess.
- **`BalanceChainValidator`** — extracted from today's IDFC/HDFC
  logic. Takes a `NormalizedTable` + mapping, returns
  exact-to-the-paisa pass/fail plus per-row direction recovery (chain
  delta, as IDFC does today). Handles multi-page chains and
  opening-balance rows.
- **`FormatSpec`** (Codable JSON) — a validated mapping, serialized:
  header/furniture patterns, column roles, date format, sign
  convention (separate debit/credit columns vs signed amount vs DR/CR
  suffix), synthetic-reference recipe for ref-less rows (today's
  balance-keyed recipe: `B<balance>D<date>A<amount>`), and a detection
  fingerprint (header regexes) so specs self-select. Hard rule: the
  format stays **purely declarative** — no expression language, ever.
- **`SpecExecutor`** — deterministically applies a `FormatSpec`;
  output still must pass `BalanceChainValidator` (specs are trusted
  for *selection*, never for *correctness*).
- **`FormatFingerprint`** — a small report generated from an
  unparseable document: container type, detected header row text,
  column count, date-shape and number-shape summaries. **Zero
  transaction data** by construction — it never includes cell values
  from body rows.
- **Resolver** (extends `ParserRegistry`) — resolution order for a
  bank-looking document: exact code parsers (existing HDFC/IDFC + all
  UPI parsers) → bundled specs → generic inference → **unsupported**
  (fingerprint + request flow; never a partial or best-guess import).

### Open source-id model (the one breaking change)

`Source` today is a closed enum baked into `contentHash`
(`"\(source.rawValue)|ref|…"`). It becomes a **string id** —
`"bank:sbi"`, `"upi:phonepe"` — with:

- the five existing raw values (`gpay`, `paytm`, `bhim`, `hdfc`,
  `idfc`) preserved **verbatim**, so every stored transaction's
  contentHash is byte-identical → no migration, dedup guarantees
  intact (regression test pins the five canonical strings);
- display name / glyph / kind resolved from a registry keyed by id,
  with a generic bank fallback for unknown ids;
- self-transfer detection generalized from "HDFC↔IDFC" to "equal
  amount, opposite direction, **any two distinct bank sources**,
  ±2 days";
- reconciliation and the "bank data wins per month" basis rule keyed
  on `kind == .bank`, unchanged in behavior.

## Import UX

- **Recognized or inferable format**: imports exactly like today —
  no new UI at all. The user never learns whether a code parser, a
  bundled spec, or fresh inference did the work.
- **Unsupported format**: a single clear sheet — "Hisab can't read
  this statement format yet." It shows which bank/app it *looks*
  like (from the fingerprint), and one primary action: **"Request
  support"**, which opens a pre-filled email (mailto:
  vedantsaboo2001@gmail.com, subject "Hisab format request",
  body = the fingerprint) via the system composer. User-initiated,
  nothing sent by the app itself. Secondary copy notes that support
  arrives in an app update.
- Corrupt/truncated statements (a chain that cannot close) get the
  same sheet with "couldn't verify this statement" wording and the
  first failing region named — never a partial import.
- Scanned/image PDFs (no text layer) are detected and explained; no
  OCR in v1.

## Our format pipeline (repo side)

- `formats/<bank>-<container>.json` specs live in the repo, each
  paired with a **synthetic fixture**; CI executes every spec against
  its fixture through `SpecExecutor` + `BalanceChainValidator`. A
  green check machine-verifies any spec, ours or contributed.
- Initial coverage: specs for the top retail banks (SBI, HDFC, ICICI,
  Axis, Kotak, IDFC FIRST, PNB, BoB, Canara, Yes) built from public
  specimen statements where obtainable; where no specimen exists, the
  bank waits for its first fingerprint (most formats are buildable
  from a fingerprint alone; occasionally we ask a requester for a
  redacted specimen).
- New specs ship bundled in the next app release; the release cadence
  is the support SLA.
- Developer contributions (spec + fixture PRs) remain welcome via
  CONTRIBUTING — that's open source, not product surface.

## Rulesets and rule suggestions

- **`rulesets/india-default.json`**: curated merchant-pattern →
  category set (Swiggy/Zomato → Food; IRCTC/Uber/Rapido → Travel;
  utilities, SIP/investment, rent patterns, …), versioned, bundled,
  seeded through the existing `Categorizer.seedRules` path.
  **User-created rules and per-transaction overrides always win**
  (existing `effectiveCategory` ordering, unchanged). Updates ship
  with app releases; CI lints pattern validity and category
  vocabulary.
- **`SuggestionEngine` (HisabCore, pure)**: scans transactions whose
  effective category is Uncategorized or Miscellaneous, clusters by
  normalized merchant/narration, and emits a queue of candidate
  rules ordered by spend impact. A candidate qualifies only if, over
  the trailing 90 days, it is
  - **substantial**: cluster total ≥ 2% of the user's total debits in
    that window, with a ₹500 floor, and
  - **frequent**: ≥ 3 transactions across ≥ 2 distinct months.
- **Prompt discipline (app)**: at most **one** suggestion per app
  launch and at most one per calendar day — "You've spent ₹4,320 on
  BLUE TOKAI across 7 payments. Categorize these?" with a category
  picker (existing categories + free text). Accept → creates an
  ordinary rule, editable like any other. Dismiss → that merchant is
  permanently muted (persisted). No notifications, no badges, no
  re-asking.

## Usefulness analysis

- **UPI coverage**: GPay + PhonePe + Paytm carry ~95% of UPI volume;
  with PhonePe added, the app-side story covers nearly everyone —
  which is why PhonePe is in-scope now.
- **Bank coverage**: bundled specs make the top banks instant;
  conservative inference silently covers well-formed long-tail
  formats; the request flow covers failures without ever showing a
  civilian a column-mapping screen. The failure UX is "email us,
  it'll be in an update" — honest and low-friction.
- **Day-one insight**: the india-default ruleset is what makes the
  dashboard meaningful before the user writes a single rule; the
  suggestion engine then grows categorization from the user's own
  spending, one polite prompt at a time.
- **Bank-only users are a first-class mode**: reconciliation needs
  both sides, but bank-statement-only users still get a categorized
  ledger and monthly analytics; the UI degrades gracefully rather
  than nagging for UPI exports.

## Generality — honest limits (v1)

- The engine assumes a **running-balance** table: Indian
  savings/current accounts, yes; credit-card statements and wallet
  ledgers, no (no balance chain). Credit cards are a future dimension
  (printed totals offer a validation path); v1 detects and says so.
- Scanned/image PDFs cannot be parsed; detected and explained.
- Single account per file, INR only. `FormatSpec` carries a currency
  field for the future; the engine asserts INR in v1.
- Password-protected PDFs already work generically (existing prompt).

## Store-review implications

This revision makes compliance strictly simpler than v1:

- **No network surface at all**: no remote fetch means Apple 2.5.2
  (code download) is moot, the privacy label stays "Data Not
  Collected", and the "makes no network requests" statements in the
  privacy policy, listing, and App Review notes remain literally true
  with no edits. The request email is a user-initiated `mailto:` via
  the system composer — the app transmits nothing.
- **Bank names in metadata**: in-app nominative use is fine (already
  cleared in review). Don't stuff bank names into App Store keywords
  or screenshots (Apple 2.3.7 / Play metadata policy); say "works
  with any Indian bank statement" and name only formats with bundled,
  tested support.
- **Finance-category declarations (Play, for later)**: Financial
  Features declaration = none-of-the-above (no accounts, transfers,
  lending); Data safety form = no data collected/shared. The
  demo-data path doubles as what Play's pre-launch bots and human
  reviewers use to see populated screens.
- **No UGC surface**: nothing user-generated is shared through the
  product; fingerprints are machine-generated and data-free.

## Testing

- TDD throughout in HisabCore (`swift test` on macOS, CI on macos-15 —
  mind Xcode 16's stricter type-check budget).
- `ColumnInference`: permuted-table torture tests — synthetic
  statements with shuffled column orders, merged debit/credit
  variants, DR/CR suffixes, missing refs, multi-page chains.
  Property: inference either recovers the exact generating mapping or
  reports unsupported — a wrong accepted mapping is a test failure,
  and so is accepting an ambiguous table.
- `SpecExecutor`: golden tests per bundled spec against its fixture.
- `FormatFingerprint`: property test that no body-row cell value ever
  appears in the output.
- `SuggestionEngine`: threshold/gating tests, mute persistence, queue
  ordering by impact.
- Migration guard: canonical-hash regression test pinning the five
  existing source ids and sample contentHashes.
- Existing 108 tests pass untouched. Existing bank code parsers stay
  in place until a bundled spec is proven **hash-identical** on the
  same fixtures (milestone 2's IDFC XLSX case); only then does the
  spec replace that code path — no behavior change for current users
  at any point.

## Milestones

1. `NormalizedTable` + `BalanceChainValidator` extraction (pure
   refactor, current parsers keep passing).
2. `FormatSpec` + `SpecExecutor` + resolver; migrate IDFC XLSX to a
   bundled spec as the proving case (hash-identical output required).
3. Conservative `ColumnInference` + silent generic import +
   unsupported-format sheet with fingerprint and email request.
4. Bundled specs for top retail banks from public specimens + CI
   fixture verification.
5. `india-default` ruleset + `SuggestionEngine` + boot-time prompt.
6. PhonePe code parser (whenever a sample arrives; parallel to all).

Android/Google Play is deliberately **after** this: the port then
targets the generalized core (spec files and rulesets are
platform-neutral JSON, shared verbatim across platforms).

## Open questions

- PhonePe sample sourcing (owner action).
- Which top-bank specimen statements are publicly obtainable; banks
  without specimens wait for their first user fingerprint.
