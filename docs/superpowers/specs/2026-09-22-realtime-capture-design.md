# Near-real-time transaction capture — design

status: approved (2026-09-22)
supersedes: the IMAP-first plan for phase-2 email ingestion (demoted to a
later fallback; see "Why not IMAP")

## The problem

A large share of Indian UPI merchants are personal names. At month-end,
when a statement is imported, those rows land in `Uncategorized` or
`Miscellaneous` and the user can no longer remember what they were for.
Memory decay, not parsing, is the failure.

The fix is to reach the user while the purchase is still fresh: capture
the bank's own transaction alert within seconds, and if Hisab cannot
categorize it, ask — right then.

## What the durable output actually is

The tempting design is to turn alerts into ledger rows. That is wrong and
this spec rejects it.

Alert messages carry no UTR or reference id. They therefore cannot join
Hisab's content-hash dedup and cannot be balance-chain validated — the two
properties that make Hisab's numbers trustworthy. Admitting them to the
ledger would trade the product's core guarantee for convenience.

**So a captured alert becomes a `PendingMemo`, and its durable output is a
*rule* (plus an optional note), not a transaction.** The loop is:

1. Alert arrives; Hisab parses it into a memo.
2. Hisab categorizes the memo's payee with the existing matcher.
3. If the result is `Uncategorized` or `Miscellaneous`, notify the user.
4. The user assigns a category, and Hisab offers to make it a rule.
5. Weeks later the statement is imported. The rule categorizes that row —
   and every other row from the same payee, past and future — correctly.

This is why the feature works without weakening the ledger: memos never
enter analytics, insights, or month buckets. The statement remains the
single source of truth. Memos are a *labelling* channel that happens to be
timely.

A memo may also carry a short user note ("lunch, split with A"). At import,
a memo that merges into a statement row transfers its note to that row.

## Capture mechanisms

### Android — `NotificationListenerService`

A user-granted special access in system settings. Not in the SMS
permission group; no Permissions Declaration Form. It reads the
notification the Messages app posts for a bank SMS, plus notifications
from UPI and bank apps directly.

`READ_SMS` is deliberately **not** used and must never be added. Play's
permitted uses are default SMS/Phone/Assistant handler only; expense
tracking is absent from the exception table; and the exception route
requires an APK published before 2019-01-01, which Hisab can never
satisfy. This is settled — do not revisit.

### iOS — one trigger-agnostic App Intent

Apple's richest option, the Shortcuts **Notification** trigger (which
documents Title/Subtitle/Body as shortcut input), exists **only in iOS
27**. It is absent from iOS 18 and iOS 26. The **Message** and **Email**
triggers go back to iOS 17 and so are available on Hisab's iOS 18 target,
but Apple documents only their *filters*, not whether they pass the
message body to the shortcut. That is unverified and cannot be resolved
from documentation.

**The design therefore refuses to depend on it.** Hisab exposes a single
App Intent:

```
AddTransactionAlert(text: String, note: String?) -> IntentResult & ProvidesDialog
openAppWhenRun = false
```

It returns a one-line dialog — "Logged ₹450 to VEDANT SABOO", or "No
transaction found in that text" when parsing declines — so a
share-sheet user gets confirmation, while an automation running with
"Notify When Run" off stays silent.

It accepts text from *any* source. Hisab ships one shortcut wrapping it,
configured to accept share-sheet text as input. That yields three paths
onto identical code, degrading gracefully:

| Path | Requires | Effort for user |
|---|---|---|
| Notification-trigger automation | iOS 27 | one-time setup, then silent |
| Message-trigger automation | iOS 17+, *and* the body reaching the shortcut | one-time setup, then silent |
| Share sheet from Messages | nothing | two taps per transaction |

If the Message trigger turns out not to pass the body, iOS loses silent
automation below iOS 27 but keeps a working manual path — and no code
changes. This is the central risk-management decision in this spec.

No Share Extension and no App Group: a shortcut added to the share sheet
reaches the App Intent inside the app process, so the SwiftData store
stays where it is. An App Group migration is deferred to the widgets work,
where it is genuinely unavoidable, so it happens once and deliberately.

iOS 17+ automations support "Run Immediately" with "Notify When Run" off,
so an automation path is genuinely silent.

Ruled out: the Wallet/Transaction trigger fires on Apple Pay, which Indian
cards do not use.

## Core: parsing and merging (Swift + Dart, parity-pinned)

New in `HisabCore` and `hisab_core`, behaviourally identical and pinned by
shared JSON fixtures, exactly as the insights engine is.

### `AlertParser`

`parse(text:receivedAt:) -> PendingMemo?`

Extracts, conservatively, and returns nil rather than guessing:

- **Amount** — Indian formats including lakh grouping: `Rs.1,234.56`,
  `INR 1234`, `₹1,23,456.78`, bare `1234.00`. Integer paise only.
- **Direction** — keyword sets. Debit: debited, spent, paid, withdrawn,
  sent. Credit: credited, received, refund. A text matching both, or
  neither, is rejected: a credit misread as a debit is worse than no
  capture.
- **Date** — `22-09-26`, `22Sep26`, `22/09/2026` and similar; absent
  means `receivedAt`.
- **Payee** — the text after `to`/`at`/`VPA`/`towards`, trimmed of
  trailing account and reference fragments.
- **VPA** — `name@handle` when present.
- **Account tail** — `A/c XX1234` when present, to attribute the memo to
  a source.

Anything not confidently parsed leaves the memo `nil` and the alert is
dropped silently. False memos are worse than missed ones.

### Deduplication — load-bearing

Android's `NotificationListenerService` fires on notification *updates*,
not just posts, and a flaky iOS automation can invoke the intent twice.
Without a guard this produces duplicate memos for one payment.

Each memo carries `captureHash = sha256(amountPaise | direction |
payeeNormalized | vpa | dateISO)`, unique. A repeat capture is a no-op.
This is the same fail-closed discipline as document `fileSHA256`.

`dateISO` is at **day granularity** (`yyyy-MM-dd`, Asia/Kolkata), never a
timestamp. An Android notification update arriving seconds later would
otherwise hash differently and defeat the guard. The deliberate cost is
that two genuinely identical payments to the same payee for the same
amount on the same day collapse into one memo. That is the right
trade — a missed duplicate memo costs one label, whereas a duplicated
memo trains a rule on a phantom payment.

### Rule-key derivation

`ruleKey(for:) -> (pattern: String, kind: .vpa | .merchant)`

Prefers the VPA local part when present, because for personal-name payees
the display name is unstable (`VEDANT SABOO`, `Vedant S`, `UPI/1234/VEDANT`)
while `someone@okaxis` is stable. Falls back to
`SuggestionEngine.normalize` (first three alpha tokens, lowercased) so
patterns match what the existing rule store already contains.

### Merge at import

When a statement is imported, each pending memo merges into a row only on
a conservative triple match: **exact amount**, **date within ±3 days**,
and **VPA match or normalized-payee match**. On merge the memo's note
transfers and the memo is retired. Unmerged memos expire after **45 days**
(statements are monthly; this leaves buffer without unbounded growth).

Memos are excluded from every analytic: month buckets, insights,
reconciliation, self-transfer detection.

## Storage and platform wiring

**Persistence.** A new `StoredPendingMemo` SwiftData model and its Drift
twin `storedPendingMemos`, holding: `captureHash` (unique), `amountPaise`,
`directionRaw`, `payee`, `payeeNormalized`, `vpa?`, `accountTail?`,
`date`, `capturedAt`, `note?`, `assignedCategory?`, `mergedTxnUUID?`,
`notifiedAt?`. Raw alert text is deliberately absent.

Capture enablement and `lastCaptureAt` are **device preferences**
(UserDefaults / SharedPreferences), not SwiftData — the same rule the
insights suppressions follow, since they describe this device rather than
the user's financial history.

**Deep links.** `CFBundleURLTypes` registering scheme `hisab` on iOS; an
`intent-filter` for the same on Android. Routes: `hisab://memo/<hash>`
and `hisab://transaction/<uuid>`. A hash that no longer resolves to a
pending memo falls back to the transaction it merged into, and failing
that opens the needs-review inbox rather than erroring.

**Notification permission** is requested lazily — at the moment the user
enables capture, never at launch — and capture still works with
notifications denied, silently filling the needs-review inbox.

**Android listener plugin.** `notification_listener_service` is the
starting choice (actively maintained, supports post and removal events).
The implementation must confirm it survives process death and reboot; if
it does not, a thin platform channel over `NotificationListenerService`
directly is the fallback. This is an implementation-time verification, not
a design assumption.

**The allowlist is Android-only.** On iOS the user's own automation or
share action *is* the filter — Hisab receives only text the user routed to
it, so there is nothing to allowlist. The bundled package-name list ships
as a JSON asset alongside the rulesets so it can be extended without code
changes, following the existing `FormatSpec` precedent.

## The correction loop

### Notification

Fired only when the memo's payee categorizes to `Uncategorized` or
`Miscellaneous` — precisely the case the user described.

- Body names the amount and payee: "₹450 to VEDANT SABOO — what was this?"
- **Actionable buttons** carry the user's three most likely categories, so
  the common case needs no app visit, plus "Later". "Most likely" is
  defined concretely: the three categories with the highest debit
  *transaction count* over the trailing 90 days, excluding
  `Uncategorized`, `Miscellaneous` and `Self Transfer`, ties broken
  alphabetically for determinism. With fewer than three available, show
  what exists.
- Capped at **10 per day** to survive a heavy UPI day.
- Alerts arriving 22:00–08:00 IST are held and delivered at 08:00, so
  Hisab never wakes anyone.

### Tap-through

`hisab://memo/<captureHash>` opens the memo in a review screen: amount,
payee, time, the source account tail, a category picker and a note field.
For an already-merged memo the link resolves to the transaction instead.

### Rule offer, with blast radius

After a category is chosen, Hisab offers: *"Always categorize
`someone@okaxis` as Food — this will also update 4 past transactions."*

The count is real, computed before committing. It matters because
recategorization here is **retroactive by construction**: category is
derived at read time by `Queries.category(of:rules:)`, never stored, so a
new rule immediately reclassifies every matching past row. Rows with an
explicit `categoryOverride` keep the user's manual choice. Showing the
count turns a surprising side effect into an informed one.

The rule is written to the existing `StoredCategoryRule` store, which
already has CRUD in Settings and a Flutter twin — so this is a new entry
point onto proven machinery, not new persistence.

### Needs-review inbox

Notifications are lossy; they get swiped away. A "Needs review" section on
the dashboard shows the pending count and lists unlabelled memos, so
nothing is silently lost.

### Capture health — the trust surface

Both mechanisms fail *silently*: Android OEM battery managers
(Xiaomi/Oppo/Vivo) kill listeners, and iOS automations quietly stop.

Settings shows "Last captured: 2 hours ago", and the dashboard warns when
capture is enabled but nothing has arrived in **3 days**, with a "test it"
action that walks the user through sending themselves a sample. Without
this the feature can be broken for weeks without the user knowing, which
would poison trust in the numbers.

## Privacy posture

The zero-network promise is preserved exactly — this feature adds no
sockets, no account, no mailbox grant. That is the main reason it is
preferred over IMAP.

Notification access is nevertheless a powerful grant, so:

- **Sender allowlist.** Only notifications from a bundled list of bank and
  UPI package names, plus the default SMS app, are examined. Everything
  else is ignored before parsing.
- **Raw text is never persisted.** Only the parsed fields reach storage.
- **On-device only**, like everything else in Hisab.
- **Prominent disclosure** before the permission request, stating plainly
  what is read and what is kept, per Play's disclosure requirements; Play
  Data safety declarations updated accordingly.
- The feature is **off by default** and reversible in one tap.

## Why not IMAP

The earlier phase-2 plan chose IMAP with an app-specific password. This
spec demotes it. Notification capture gets the same near-real-time memo
while keeping zero-network, and avoids a 16-character app password, an
all-or-nothing mailbox grant, and a privacy-label rewrite on both stores.
IMAP remains a reasonable *later* fallback for banks that only ever email,
but it is no longer the primary route.

## Phase B — iOS share-sheet file import

Independent of everything above and deliberately cheap.

Declaring `CFBundleDocumentTypes` plus `LSSupportsOpeningDocumentsInPlace`
(via xcodegen's `info:` block, since the target currently uses
`GENERATE_INFOPLIST_FILE`) makes Hisab appear as a destination for PDF,
CSV, XLSX, XLS and TXT files from Files, Mail, Gmail and the share sheet.
The incoming URL is handled with `onOpenURL` and fed to the existing
`ImportResolver` pipeline — the same silent format detection shipped in
1.2, so there is no source to pick.

No Share Extension and no App Group, for the reasons given above.

## Testing

- `AlertParser` parity fixtures shared by Swift and Dart, covering each
  bank template shape, lakh grouping, credit-vs-debit, missing date, and
  the reject cases. Same discipline as `insights-parity*.json`.
- Dedup: a repeated identical capture must not create a second memo.
- Merge: exact-amount/±3-day/payee triple match, plus non-merge cases.
- Retroactive rules: adding a rule reclassifies past rows while leaving
  `categoryOverride` rows untouched.
- Notification cap and quiet-hours holding.
- A device pass is mandatory before release. The insights work shipped two
  bugs that an implementation *and* a full code review both missed and only
  a real device caught; capture, notification actions and deep links are
  all in that same category of "looks right in code, silently does nothing".

## Explicitly out of scope

Widgets, Siri data surfaces and the broader Shortcuts action catalogue.
They need the App Group migration and, more importantly, their design
depends on what dogfooding teaches about which data is worth surfacing.
Deciding that now would be guessing.

## Version

Ships as **1.3.0** to TestFlight for dogfooding, with a sideload APK for
the Android half (TestFlight covers only iOS, and OEM battery-kill
behaviour cannot be evaluated on an emulator).
