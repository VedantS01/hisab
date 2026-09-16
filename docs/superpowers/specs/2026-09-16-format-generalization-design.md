# Format Generalization — Design

Date: 2026-09-16 · Status: approved in discussion, pending spec review
Owner: Vedant (decisions confirmed interactively)

## Goal

Make Hisab useful beyond its author's own accounts: parse statements
from **arbitrary Indian banks**, keep UPI-app support growing (add
**PhonePe**), and ship a **standard India-wide categorization ruleset**
— all without weakening the two founding guarantees:

1. **Privacy**: zero network requests by default; statements never
   leave the device.
2. **Correctness**: nothing unvalidated ever enters the ledger; every
   bank parse must prove itself **to the paisa**.

Out of scope here (own later brainstorms): the Android/Google Play
port (which will port the *generalized* core produced by this work),
and any LLM-assisted parsing.

## Decisions (confirmed 2026-09-16)

| Question | Decision |
|---|---|
| Order of the three workstreams | Formats → rulesets (rides along) → Android |
| Unknown-format UX | Self-serve generic engine + mapping UI, with an opt-in community sharing loop |
| UPI apps | Stay curated **code parsers** (few players, printed-totals validation); add PhonePe now |
| Spec/ruleset distribution | **Bundled** in releases (zero-network default intact) + explicit opt-in "Check for new formats" fetch of a static catalog |
| Engine architecture | **C — inference proposes, balance chain disposes, specs remember** (A "specs only" and B "inference only" are strict subsets) |

## Key insight

Every Indian bank statement, whatever the container (PDF, XLSX, XLS,
TXT, CSV), reduces to the same table: date · narration · reference ·
debit/credit (or signed amount) · **running balance**. The balance
column is a checksum over the whole statement: a candidate column
mapping is accepted **only** if `prev ± amount == next` closes exactly,
row by row, to the paisa. That turns "we hand-validated each format
against real samples" into "**every import validates itself on the
user's own file**" — the property that makes generalization safe.

UPI-app exports have no balance column, so they cannot self-validate;
that is why they remain curated code parsers validated against each
format's printed totals.

## Architecture (HisabCore `GenericBank` module)

All pure Swift, TDD'd with synthetic fixtures, like the rest of
HisabCore.

- **`NormalizedTable`** — `[[Cell]]` plus per-row provenance. The five
  container readers (geometric PDF, MinimalZip/XLSX, MinimalXLS, TXT
  ruler-slicing, CSV) already effectively produce this; they get a
  common output type instead of each feeding a bespoke parser.
- **`ColumnInference`** — proposes candidate role assignments
  (date / narration / reference / debit / credit / amount / balance)
  from content shape: date-like columns, numeric columns, and the one
  column where a balance chain can close. Emits candidates in
  confidence order; never decides alone.
- **`BalanceChainValidator`** — extracted from today's IDFC/HDFC
  logic. Takes a `NormalizedTable` + mapping, returns
  exact-to-the-paisa pass/fail plus the recovered direction per row
  (direction recovery via chain delta, as IDFC does today). Also
  handles multi-page chains and opening-balance rows.
- **`FormatSpec`** (Codable JSON) — a validated mapping, serialized:
  header/furniture patterns to strip, column roles, date format, sign
  convention (separate debit/credit columns vs signed amount vs
  DR/CR suffix), synthetic-reference recipe for ref-less rows (same
  balance-keyed recipe as today: `B<balance>D<date>A<amount>`),
  detection fingerprint (header regexes) so specs self-select.
- **`SpecExecutor`** — deterministically applies a `FormatSpec` to a
  `NormalizedTable`; output still must pass `BalanceChainValidator`
  (specs are trusted for *selection*, never for *correctness*).
- **Resolver** (extends `ParserRegistry`) — resolution order for a
  bank-looking document:
  1. exact code parsers (existing HDFC/IDFC + all UPI parsers),
  2. bundled specs, 3. user's local specs, 4. fresh inference,
  5. → "needs mapping" (never a silent best guess).

### Open source-id model (the one breaking change)

`Source` today is a closed enum baked into `contentHash`
(`"\(source.rawValue)|ref|…"`). It becomes a **string id** —
`"bank:sbi"`, `"upi:phonepe"` — with:

- the five existing raw values (`gpay`, `paytm`, `bhim`, `hdfc`,
  `idfc`) preserved **verbatim** as ids, so every stored transaction's
  contentHash is byte-identical → no migration, dedup guarantees
  intact (regression test asserts the five canonical strings);
- display name / glyph / kind resolved from a registry keyed by id,
  with a generic bank fallback for unknown ids;
- self-transfer detection generalized from "HDFC↔IDFC" to "equal
  amount, opposite direction, **any two distinct bank sources**,
  ±2 days";
- reconciliation and the "bank data wins per month" basis rule keyed
  on `kind == .bank`, unchanged in behavior.

## Mapping assistant (app)

When resolution ends at "needs mapping", the import sheet presents:

1. the detected table, rendered as extracted (first ~15 rows);
2. tappable column headers cycling through roles, a date-format
   picker, and a sign-convention picker — pre-filled with inference's
   best candidate;
3. a **live balance-chain indicator**: red with the first failing row
   highlighted until the whole statement closes, green when it does.
   The Import button enables only on green.

On import: the mapping is saved as a local spec (same bank never asks
again). A "Share this format" action exports the spec JSON — column
mappings and patterns only, zero personal data — via the share sheet
or a pre-filled GitHub issue URL. Sharing is manual and optional;
nothing is transmitted by the app itself.

Error handling: container unreadable → existing unsupported-file
error; table found but no mapping can close the chain (corrupt or
truncated statement) → explicit "couldn't verify this statement"
state with the failing row shown, never a partial import.

## Community loop (repo + site)

- `formats/<bank>-<container>.json` specs live in the repo, **each
  paired with a synthetic fixture** (generated like today's test
  fixtures — never real statements). CI executes every spec against
  its fixture through `SpecExecutor` + `BalanceChainValidator`;
  a green check machine-verifies a contribution, so no maintainer
  needs a real sample.
- CI builds `catalog.json` (spec index + rulesets + min-app-version)
  onto the existing GitHub Pages site.
- The app bundles all specs at release; Settings gains
  **"Check for new formats"** — an explicit, user-initiated fetch of
  that static catalog (the only network call in the product, clearly
  labeled; privacy copy updated from "no network requests" to "no
  network requests except this button").
- CONTRIBUTING gets a "contribute a format — no Swift required"
  recipe: run the mapping assistant on your own statement, share the
  spec, add a synthetic fixture (template provided), open a PR.

## Standard rulesets

- `rulesets/india-default.json`: curated merchant-pattern → category
  set (Swiggy/Zomato → Food; IRCTC/Uber/Rapido → Travel; utility,
  investment/SIP, rent patterns, …), versioned, bundled, refreshed via
  the same catalog.
- Seeded through the existing `Categorizer.seedRules` path as
  system-provided rules; **user-created rules and per-transaction
  overrides always take precedence** (existing `effectiveCategory`
  ordering, unchanged).
- Community PRs edit the JSON; CI lint checks pattern validity and
  category vocabulary.

## PhonePe (sixth UPI source)

Code parser, same discipline as the other four: built against a real
sample, validated against the statement's printed totals, synthetic
fixture for CI. **Blocked on obtaining one sample statement** (owner's
or a willing friend's; the file never leaves the machine, per standing
rule). Ships whenever the sample exists — independent of everything
above.

## Testing

- TDD throughout in HisabCore (`swift test` on macOS, CI on macos-15 —
  mind Xcode 16's stricter type-check budget).
- `ColumnInference`: permuted-table torture tests — synthetic
  statements with shuffled column orders, merged debit/credit
  variants, DR/CR suffixes, missing refs, multi-page chains; property:
  inference + validation either recovers the exact generating mapping
  or reports "needs mapping", never a wrong accepted mapping.
- `SpecExecutor`: golden tests per bundled spec against its fixture.
- Migration guard: canonical-hash regression test pinning the five
  existing source ids and sample contentHashes.
- Existing 108 tests pass untouched. Existing bank code parsers stay
  in place until a bundled spec is proven **hash-identical** on the
  same fixtures (milestone 2's IDFC XLSX case); only then does the
  spec replace that code path — no behavior change for current users
  at any point.

## Usefulness analysis

A random user's value from Hisab is roughly: *my UPI apps parse* ×
*my bank parses* × *the dashboard means something on day one*.

- **UPI coverage**: GPay + PhonePe + Paytm carry ~95% of UPI volume;
  with PhonePe added, the app-side story covers nearly everyone. This
  is why PhonePe is in-scope now rather than left to contribution.
- **Bank coverage**: the generic engine covers the long tail, but the
  mapping UI must be the *exception*, not the onboarding experience —
  a non-technical user hitting a column-tagging screen on first import
  will bounce. Mitigation: seed bundled specs for the top ~10 retail
  banks (SBI, HDFC, ICICI, Axis, Kotak, IDFC FIRST, PNB, BoB, Canara,
  Yes) early — from public sample statements and community
  contributions — so the common path is zero-touch.
- **Day-one insight**: the india-default ruleset is what makes the
  dashboard meaningful before the user writes a single rule; without
  it everything lands in Uncategorized and the product looks empty.
- **Bank-only users are a first-class mode**: reconciliation needs
  both sides, but a user who imports only bank statements still gets
  a categorized ledger and monthly analytics (everything is
  "Miscellaneous"-by-default until rules bite). The UI must degrade
  to this gracefully rather than nag about missing UPI exports.

## Generality — honest limits (v1)

- The engine assumes a **running-balance** table; that holds for
  Indian savings/current-account statements but not credit-card
  statements or wallet ledgers (no balance chain). Credit cards are a
  future dimension (they do print totals, so a validated path exists);
  v1 detects and says "not a bank account statement" rather than
  guessing.
- **Scanned/image PDFs** (no text layer) cannot be parsed; detect and
  explain, no OCR in v1.
- Single account per file, INR only. `FormatSpec` carries a currency
  field for the future, but the engine asserts INR in v1.
- Password-protected PDFs already work generically (existing prompt).

## Store-review implications

- **Remote specs are data, not code** (Apple guideline 2.5.2 / Play
  equivalent): specs and rulesets are declarative JSON interpreted by
  a fixed, shipped engine. Hard rule for all future work: the spec
  format must never grow an expression language or anything
  eval-like, or the opt-in fetch becomes downloadable code.
- **Privacy label stays "Data Not Collected"**: the opt-in catalog
  fetch sends no user data — it is a plain GET of a static file. But
  our App Review notes and privacy policy currently say "no network
  requests"; the next submission that ships the button must update
  both to "no network requests except the explicit, user-initiated
  format-catalog check (a static file on GitHub Pages; GitHub sees
  your IP as with any download)". Never let marketing copy and
  review-notes copy drift apart — that mismatch is what 2.1 rejections
  are made of.
- **Bank names in metadata**: in-app nominative use is fine (already
  cleared in review), but don't stuff dozens of bank names into App
  Store keywords/screenshots or Play listing text (Apple 2.3.7 /
  Play metadata policy treat that as third-party-brand keyword
  spam). Say "works with any Indian bank statement" and name only the
  formats with bundled, tested specs.
- **Finance-category declarations**: Hisab performs no financial
  services (no accounts, transfers, lending). On Play this still
  requires the **Financial Features declaration** (answer:
  none-of-the-above) and the **Data safety form** (no data
  collected/shared — same reasoning as Apple's label). Play's
  pre-launch report robots will explore the app: the demo-data path
  doubles as the way those bots (and human reviewers) see populated
  screens.
- **Community content**: shared specs contain mappings and patterns
  only — no UGC surface, no moderation obligations. Keep it that way:
  the share flow exports machine-generated JSON, never free text or
  statement excerpts.

## Milestones

1. `NormalizedTable` + `BalanceChainValidator` extraction (pure
   refactor, current parsers keep passing).
2. `FormatSpec` + `SpecExecutor` + resolver; migrate IDFC XLSX to a
   bundled spec as the proving case (hash-identical output required).
3. `ColumnInference` + mapping assistant UI + local spec store.
4. Repo `formats/` + fixtures + CI verification + `catalog.json` +
   opt-in fetch + CONTRIBUTING recipe.
5. `india-default` ruleset + seeding + catalog refresh.
6. PhonePe parser (whenever the sample arrives; parallel to all).

Android/Google Play is deliberately **after** this: the port then
targets the generalized core (spec files and rulesets are
platform-neutral JSON, shared verbatim across platforms).

## Open questions

- PhonePe sample sourcing (owner action).
- Whether "Check for new formats" lands in the same release as specs
  or a later one (bundled-only is a complete v1 of this design).
