# Hisab (हिसाब)

<img src="docs/brand/icon.png" width="96" align="right" alt="Hisab icon: a red bahi-khata ledger with a rupee glyph" />

A private, on-device iOS app for personal expense analysis. Import
Google Pay / Paytm transaction exports and HDFC / IDFC bank statements;
Hisab parses them deterministically, organizes everything into monthly
time buckets, cross-checks payment-app records against bank statements,
and shows a dashboard of where the money went.

- **On-device only** — SwiftUI + SwiftData, no server, no accounts, no
  network calls. Your financial data never leaves the phone.
- **Monthly time buckets, derived not stored** — importing any file
  auto-creates the months it covers; a yearly bank statement lights up
  all twelve months in its column. Pin future months to mark them
  "awaiting".
- **Reconciliation** — tiered matching (UPI reference first, then
  amount + date window) tells you which app payments the bank confirms,
  which are missing, and what you spent outside the apps entirely.
- **Bank-basis analytics** — months with a bank statement trust only
  the bank (no double counting with app exports); months without fall
  back to payment-app data, clearly labeled.
- **HisabCore** — all parsing, dedup, bucketing, reconciliation, and
  analytics logic lives in a pure-Swift package with a full XCTest
  suite that runs on macOS in milliseconds.
- **Bahi-khata design language** — palette and icon borrow from the
  traditional red-cloth Indian ledger.

## Screenshots

| Dashboard | Buckets | Reconciliation | Transactions |
|---|---|---|---|
| ![Dashboard](docs/brand/dashboard.png) | ![Buckets](docs/brand/buckets.png) | ![Reconciliation](docs/brand/reconciliation.png) | ![Transactions](docs/brand/transactions.png) |

## Build & run

Requirements: Xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
make gen        # xcodegen generate -> Hisab.xcodeproj
make test       # HisabCore unit tests (swift test)
make build      # build for the iPhone simulator
make run        # boot simulator, install, launch
```

Then in the app: **Settings → Load demo data** fills three months of
synthetic GPay + HDFC statements so every screen is explorable.

## Status

Core engine, dashboard, buckets grid, import flow, reconciliation, and
settings are working end-to-end against the synthetic statement format.
The four real-format parsers (GPay, Paytm, HDFC, IDFC) land next —
they're written against private sample statements (gitignored
`samples/`; tests use synthetic fixtures only).

Design spec: [`docs/superpowers/specs/2026-09-05-hisab-design.md`](docs/superpowers/specs/2026-09-05-hisab-design.md)
