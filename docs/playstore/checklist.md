# Google Play — publishing formalities checklist

Status: researched 2026-09-16. The Android app does not exist yet (the
port is a separate decision — KMP vs Flutter vs Swift-on-Android);
everything here is the *store-side* work, most of which can start now.
Owner actions are marked **[Vedant]**.

## 1. Long-lead items (start before the app exists)

- **[Vedant] Create the Play Console developer account** —
  play.google.com/console, one-time $25 fee, personal account under
  vedantsaboo2001@gmail.com. Identity verification (government ID +
  address) can take days; the public developer name and a contact
  email are shown on the listing. No D-U-N-S needed for personal
  accounts.
- **The 12-testers / 14-days rule (critical path).** Personal accounts
  created after 2023-11-13 cannot publish to production until the app
  has run a **closed test with ≥12 opted-in testers for 14 continuous
  days**, and since 2026 Google also checks the testers *actually
  used* the app — inactive installs don't count, and dropping below 12
  resets the clock. Passing the threshold makes you *eligible to
  apply* for production access; Google can still ask for more testing.
  **[Vedant]** line up ~15 friends/colleagues with Android phones in
  advance (buffer above 12). The demo-data path gives testers
  something real to do without their own statements.
- **Package name**: reserve `com.vedants.hisab` (matches the iOS
  bundle id). Package names are permanent per app.

## 2. Technical requirements (for the future Android build)

- Upload format is **AAB** (Android App Bundle), not APK, with
  **Play App Signing** (Google holds the release key; we keep an
  upload key — generate and back it up).
- **Target API level**: new apps submitted after 2026-08-31 must
  target **Android 16 (API 36)**; an extension to 2026-11-01 can be
  requested. Build against the newest stable SDK from day one.
- Pre-launch report robots will crawl the app on real devices —
  the Settings → Load demo data path doubles as what they (and any
  human reviewer) will see populated.

## 3. Store listing (can be drafted now)

- App name: **"Hisab - UPI Statement Ledger"** (28 chars, fits Play's
  30-char limit; also keeps parity with the App Store name).
- Short description: ≤80 chars, e.g. *"Private, on-device ledger from
  your UPI and bank statements. Zero network."*
- Full description: ≤4000 chars — adapt the App Store description.
- Assets: hi-res icon **512×512 PNG** (re-render from
  `tools/render-icon.swift`), **feature graphic 1024×500** (new asset
  to design), ≥2 phone screenshots (use the same set as
  `docs/appstore/`, re-framed for Android once the app exists).
- Category: **Finance** · free · no ads · contact email required.
- Privacy policy URL (required): https://vedants01.github.io/hisab/#privacy
  — already live; it is platform-neutral, no edits needed.

## 4. App content declarations (Play Console → App content)

| Form | Answer for Hisab |
|---|---|
| Data safety | **No data collected, no data shared** — all parsing/storage on-device, zero network requests (same reasoning as Apple's "Data Not Collected" label) |
| **Financial features declaration** (required for Finance category) | **"My app doesn't provide any financial features"** — Hisab is an offline organizer of documents the user already has: no loans, no banking, no payments, no account aggregation. India's RBI/digital-lending approval list applies to loan apps only, not to us |
| Content rating (IARC questionnaire) | No objectionable content → expect **Everyone / 3+ / PEGI 3** |
| Target audience | **18+** (finance content; avoids all Families-policy obligations) |
| Ads | None |
| News app / COVID app / Government app | No / No / No |
| Account deletion requirement | N/A — the app has no accounts or login |

## 5. Policy cautions (mirror of the App Store section in the design spec)

- Bank/UPI names stay **nominative** — text labels for supported
  formats, no logos, no implied affiliation, and never stuffed into
  the listing title/description as keyword spam (Play metadata
  policy).
- The zero-network claim must stay literally true on Android too —
  same hard rule as iOS: no analytics SDKs, no crash reporters, no
  fetches. (Standard Android template projects often bundle Firebase —
  don't.)
- Emails via the system mail intent (`mailto:`) keep the request flow
  compliant, identical to iOS.

## 6. Suggested sequence

1. **[Vedant]** open the developer account + identity verification (days).
2. Reserve package name by creating the app record (can be done with a
   placeholder internal-testing build once any Android build exists).
3. Draft listing text/assets + fill all §4 declarations (no build needed).
4. When the Android port lands: internal testing → **closed testing
   with 12+ active testers for 14+ days** → apply for production.
5. Production rollout (staged % rollout recommended), then add the
   Play badge next to the App Store badge in the README.

Sources: Play Console Help — app testing requirements for new personal
accounts (support.google.com/googleplay/android-developer/answer/14151465),
target API level requirements (answer/11926878), Financial features
declaration (answer/13849271), Financial Services policy (answer/9876821).
