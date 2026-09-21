# Spending Insights — design

Date: 2026-09-18 · Status: implemented (2026-09-21)
Scope: iOS (HisabCore + Hisab app) and Android (hisab_core + Flutter
app), shipped together with parity tests.

## Goal

Make the dashboard proactive: surface neutral, factual observations
about the user's own spending — computed on-device from already
imported statements — so users can make informed choices without
digging. No configuration required from the user, no budgets (a
possible later phase), no advice, no notifications.

## Constraints (load-bearing)

- 100% on-device, zero network. Nothing new for store review: no
  notification permission, no data collection, ephemeral computation.
- Data changes only at import; "proactive" = computed at app boot and
  after each successful import.
- Tone is **neutral observation**: amounts, percentages, dates. No
  advice verbs, no judgment. ("Food: ₹8,400 — up 40% vs your 3-month
  average.") This keeps the Finance-category compliance surface at
  zero.
- Politeness principle carried over from SuggestionEngine: the UI is
  furniture, not notification — no badges, no unread counts, no
  animation on appearance.

## Architecture: detector pipeline + ranker (approach A)

One pure function in each core:

```
generateInsights(input, config, suppressed) -> [Insight]
```

- `input`: the visible-transaction set analytics already uses
  (deduped, self-transfers excluded, basis rule applied) + the
  coverage map + a now-in-IST timestamp.
- `config`: parsed `insights-config.json` (bundled, see below).
- `suppressed`: dismissed insight ids + muted merchants/categories.

Three independent, pure detectors emit typed `Insight` values with
internal scores; an `InsightRanker` merges, applies suppressions and
collision rules, and returns at most `maxCards` for the dashboard.
No persistence of derived data — insights are recomputed from scratch
each boot/import. **Corrected after the 1.2 whole-branch review:** a pass
is not "microseconds". Measured at 1,200 records it was ~900 ms (Dart)
and ~660 ms (Swift, debug) before the merchant-key hoists, because the
outlier loop re-normalized the whole history once per recent row. After
those hoists the same pass is ~17 ms (Dart) and ~53 ms (Swift, debug);
it is linear in the record count, and at 5,000 records it is ~30 ms
(Dart) / ~110 ms (Swift, release). That is cheap enough to stay on the
main thread and recompute per render, which is the property this
paragraph was claiming — but the original number was wrong by three
orders of magnitude and `InsightsPerformanceTests` /
`insights_performance_test.dart` now pin it. The only state is user
intent (suppressions),
platform-local (UserDefaults / SharedPreferences).

### Complete-month rule

All month-level comparisons use **complete** months per the coverage
map; the in-progress/partial bucket is excluded. This prevents the
"spending down 60%!" lie on a half-imported month.

### Insight identity

Each insight has a stable content-derived id (SHA256 over type +
anchor + the material number, in canonical form, shared across
platforms). Dismissals key on it: the same observation never returns
after dismissal, but materially new news (Netflix ₹649 → ₹799) is a
new id and appears once.

## Detectors

### 1. TrendDetector (category trends)

For each category with spend in the latest complete month: compare to
the trailing `windowMonths` (3) complete months' average. Emit when
|change| ≥ `minPct` (25) **and** |change| ≥ `minAbsPaise` (₹500).
Both directions. Concentration annotation: if one transaction
accounts for ≥ `concentrationPct` (70) of the month's spend in that
category, the card says
"driven by one ₹X purchase at M" — and no separate outlier card is
emitted for that transaction (collision rule).

### 2. RecurrenceDetector

Group by normalized merchant (SuggestionEngine normalizer, reused).
A series is recurring when ≥ `minOccurrences` (3) occurrences at
stable intervals (monthly = median gap 28–33 days, weekly = 6–8) with
amount spread ≤ `amountSpreadPct` (15) of the median. Emits:

- **New recurring** — series began within `newWithinMonths` (2).
- **Recurring changed** — latest amount ≥ `changedPct` (10) off the
  series median.
- **Committed spend** — one standing summary card when ≥ 2 active
  series exist: monthly total + count, where a weekly series
  contributes its median amount × 52/12.

A series is **active** while its most recent payment is within
`activeWithinCadences` (2) cadence-lengths of now, so a cancelled
subscription stops counting as committed spend instead of lingering
forever.

### 3. AnomalyDetector

Looks at the last `lookbackDays` (35) only.

- **Possible duplicate** — same normalized merchant, same amount,
  same IST day; tightened to within `duplicateWindowMinutes` (10)
  when the source carries timestamps.
- **Outlier amount** — merchant has ≥ `minPriors` (5) prior txns and
  the latest is ≥ `outlierMultiple` (3) × merchant median **and**
  ≥ `outlierMinPaise` (₹1,000).

## Ranking & lifecycle

- Score = rupee magnitude (normalized against the month's total
  debits, in permille) × config type weight. No separate recency
  factor: every detector already bounds its window, so everything
  emitted is current by construction. **Integer arithmetic only** —
  a float score risks the two platforms ordering cards differently.
  Default weight order:
  duplicate > recurring new/changed > outlier > trend.
- Cap `maxCards` (5), variety guard `maxPerType` (3).
- Collision rules — one event, one card: recurrence card supersedes
  outlier for the same transaction; concentration annotation
  supersedes a separate outlier card (see TrendDetector); a
  possible-duplicate card supersedes an outlier card for the same
  transactions (a double charge that is also unusually large is one
  event, and "you may have paid twice" is the more actionable
  reading).
- **Dismiss** (✕): stores the insight id locally; pruned when the
  insight no longer generates.
- **Mute** (overflow/long-press): per-merchant (recurrence/anomaly)
  or per-category (trend) muted sets, same mechanism as
  SuggestionEngine's.
- **Committed-spend card** is pinned last while eligible and updates
  in place. It is neither dismissible nor mutable: it is a single
  standing summary, and there is no sensible per-merchant target to
  mute it by.
- No insight history. The transactions are the history.

## Dashboard UI

"For you" strip at the top of the Dashboard (between month header and
existing analytics): horizontally scrollable cards, next card peeking
(~85% width), max 5. No insights → no strip (no empty state).

Card anatomy (all types): type glyph + caption label (TREND /
RECURRING / UNUSUAL / COMMITTED), one-line headline with the number,
one-line context, quiet ✕ top-right, overflow (long-press) with the
mute action. Kagaz-cream cards; delta arrows Khata Red (spend up) /
Hara (spend down); Sona gold accent for anomaly + committed cards.
No in-card charts in v1.

Tap-through — every card lands on evidence via an **evidence sheet**
listing exactly the transactions behind the number (a self-contained
sheet rather than driving the Transactions tab: same "show me why",
no tab-selection state plumbed through either app). The
committed-spend card's sheet lists the active series instead
(merchant, cadence, amount, first-seen).

Accessibility: VoiceOver/TalkBack read the full sentence; Dynamic
Type scaling. iOS: `ScrollView(.horizontal)` +
`containerRelativeFrame`; Flutter: horizontal page-style `ListView`.

## Config

`insights-config.json` bundled in both cores, synced by
`tool/sync_assets.sh` (CI `--check` guards drift). Numbers only, no
logic. Keys as named in the detector sections plus `rankerWeights`,
`maxCards`, `maxPerType`, and a `version` int. Tuning ships in app
updates by editing one file.

## Testing & parity

- TDD per detector with synthetic fixtures in both suites.
- **Parity fixture**: one shared canonical JSON — input transactions
  + expected insights (ids, types, order) — asserted identically by
  a Swift test and a Dart test (same pattern as the pinned content
  hashes and `supportedFormatNames`).
- Edge pins: partial-month exclusion; collision rules; dismissal-id
  stability (same content → same id, new material number → new id);
  mute suppression; config load + hygiene (all keys present, sane
  ranges).
- Demo dataset extended to deterministically produce ≥ 1 card of
  every type — end-to-end UI verification in simulator/emulator and
  honest store screenshots. Demo statement dates are shifted forward
  at load time so the set keeps producing cards as months pass
  (a frozen demo would age out of every detector's window).

## Out of scope (deliberate)

Budgets/limits and pace projections; local notifications; insight
history; per-user tunable thresholds; sparklines in cards; any
persistence of derived analytics.
