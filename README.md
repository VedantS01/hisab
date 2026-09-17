<p align="center"><img src="docs/brand/logo.png" width="440" alt="Hisab — हिसाब"></p>

# Hisab (हिसाब)

![CI](https://github.com/VedantS01/hisab/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/license-Apache--2.0-A4243B)
[![App Store](https://img.shields.io/badge/App_Store-Hisab-0D96F6?logo=apple&logoColor=white)](https://apps.apple.com/app/id6809138684)

**Now on the App Store:** [Hisab — UPI Statement Ledger](https://apps.apple.com/app/id6809138684)

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
- **Reconciliation-nature bank data** — bank rows confirmed against an
  app payment are evidence, never duplicate records; bank-only spending
  lands as "Miscellaneous"; HDFC↔IDFC self transfers are recognized and
  excluded from spend/income entirely.
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

Feature-complete. All real-format parsers are in and validated
to-the-paisa against actual statements (each parser's debit/credit sums
match the statement's own printed totals exactly):

| Source | Formats | Notable engineering |
|---|---|---|
| Google Pay | PDF | block state machine over PDFKit text |
| Paytm | PDF + XLSX | page-order-independent amount pairing; year inference |
| BHIM UPI | PDF | single-line rows; failed transactions excluded |
| IDFC FIRST | PDF + XLSX | direction recovered from the running-balance chain |
| HDFC | PDF (password-supported) + TXT + XLS | geometric PDF reconstruction; dash-ruler fixed-width slicing; a from-scratch CDF/BIFF8 reader |
| **Any Indian bank** (running-balance statements) | CSV + XLSX + XLS + TXT + text-layer PDF | generic engine: conservative column inference + declarative FormatSpecs, accepted only when the balance chain closes to the paisa |

Bundled FormatSpecs make the majors instant: SBI, ICICI (two layouts),
Axis (two layouts), Kotak — plus provisional PNB and Bank of Baroda.
Anything else with a running balance goes through inference, which
either proves its parse against the statement's own balance column or
refuses (an in-app request then emails us a data-free format
fingerprint, and support ships in an update — the engine never
guesses).

**Android**: a full-parity Flutter port lives in `hisab_flutter/` —
a pure-Dart `hisab_core` mirrors the Swift core module-for-module, and
a pinned-hash test suite proves that content hashes are **byte-identical
across platforms**: importing the same statement on iPhone and Android
produces the same transaction identities. All formats above are
supported on Android except the IDFC *PDF* rendition (a PDF-library
glyph issue would corrupt references; the IDFC XLSX rendition of the
same statement parses perfectly). Play Store release in progress.

Spreadsheet support is dependency-free: .xlsx via a minimal zip reader
over Apple's Compression framework plus an XMLParser sheet reader, and
legacy .xls via a purpose-built CDF/OLE2 + BIFF8 record reader
(CONTINUE-aware SST included). Dual-format
imports of the same statement dedup to zero via reference-keyed,
refund-safe content hashes. Real statements live in the gitignored
`samples/`; tests use synthetic fixtures only.

## Contributing

Missing your bank? The fastest contribution is a **FormatSpec** — a
declarative JSON layout description, no Swift required; CI
machine-verifies it against a synthetic fixture. UPI apps and exotic
formats remain code parsers. See [CONTRIBUTING.md](CONTRIBUTING.md)
for both recipes. Real statements never enter the repo.

Site & privacy policy: https://vedants01.github.io/hisab/ ·
License: [Apache-2.0](LICENSE)

Design spec: [`docs/superpowers/specs/2026-09-05-hisab-design.md`](docs/superpowers/specs/2026-09-05-hisab-design.md)
