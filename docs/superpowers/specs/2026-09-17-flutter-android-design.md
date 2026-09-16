# Flutter Android Port — Design

Date: 2026-09-17 · Status: IMPLEMENTED (Vedant: "Port it fully to use
Flutter"; Android-only for now; full format parity in v1)

## Goal

Ship Hisab on Google Play as a Flutter app with **full feature and
format parity** with iOS 1.1.0, while the native iOS app stays on the
App Store. The Flutter codebase is kept cross-platform-clean so it
*could* later serve iOS, but nothing in v1 targets that.

## Non-negotiable invariants

1. **Hash parity**: Dart `contentHash` builds byte-identical canonical
   strings to Swift's; the Dart pin test asserts the SAME six hex
   digests pinned in `SourceMigrationTests.swift`. A statement imported
   on either platform yields identical transaction identities.
2. **Correctness**: nothing unvalidated enters the ledger; bank parses
   must close the running-balance chain to the paisa (same engine
   semantics, ported).
3. **Privacy**: zero network. No networking package anywhere in the
   dependency tree; the only outbound path is a user-initiated mailto.
4. **Single source of truth for data assets**: `formats/*.json`,
   `rulesets/india-default.json`, and test fixtures live in
   HisabCore; `tool/sync_assets.sh` copies them into the Flutter tree
   and CI fails when they drift.

## Layout (monorepo)

```
hisab_flutter/                      Flutter app, applicationId com.vedants.hisab
  pubspec.yaml                      deps: hisab_core, drift, fl_chart,
                                    file_picker, url_launcher, path_provider,
                                    share_plus (no network packages)
  lib/ (theme, storage, services, screens, widgets)
  assets/formats/ assets/rulesets/  synced from HisabCore
  packages/hisab_core/              pure Dart, mirrors HisabCore module-for-module
    lib/src/*.dart                  year_month, money, domain, content_hash,
                                    dedup, reconciliation, self_transfers,
                                    categories, analytics, coverage,
                                    suggestion_engine, generic_bank/*, parsers/*
    test/                           ported test suites + synced fixtures
tool/sync_assets.sh                 copy + drift check
```

## Key porting decisions

- **IST**: fixed UTC+05:30 offset (IST has no DST) — a small
  `istDate()` helper over `DateTime.utc`, no timezone package.
- **Money**: Dart `int` is 64-bit; port `signedPaise`/`formatPaise`
  verbatim (Indian digit grouping).
- **SHA256**: `crypto` package over the identical canonical strings.
- **Containers**: CSV/TXT trivial; XLSX via `archive` (zip) + `xml`;
  XLS = direct port of MinimalXLS (CDF/OLE2 + BIFF8, CONTINUE-aware
  SST); **PDF via `syncfusion_flutter_pdf`** (community license):
  `PdfTextExtractor.extractTextLines()` gives per-line/word bounds —
  covers text-layer parsing (GPay/Paytm/BHIM/IDFC) and the geometric
  HDFC reconstruction; supports password-protected PDFs.
- **PDF risk, named**: Syncfusion's text ordering ≠ PDFKit's. Every
  PDF parser is re-validated **to the paisa against the real
  statements in gitignored `samples/`** via a local-only Dart harness
  (skipped when `samples/` is absent, e.g. on CI); synthetic fixtures
  guard CI.
- **Storage**: drift (SQLite) tables mirroring the SwiftData models
  (StoredDocument/StoredTransaction/StoredCategoryRule/StoredMatch/
  PinnedMonth) with a UNIQUE index on contentHash; file-level SHA256
  duplicate check preserved.
- **UI**: five screens mirroring iOS (Dashboard w/ fl_chart trend +
  हिसाब masthead, Buckets dynamic grid, Transactions w/ filters +
  category editing, Reconciliation, Settings w/ demo data / erase /
  rules editor), import flow (file_picker → resolver → report /
  password / format-request sheet), suggestion prompt (≤1/day, muted
  merchants), format-request mailto (url_launcher). Same palette
  (KhataRed #A4243B, Kagaz, Sona), Noto Sans Devanagari for हिसाब.
- **Demo data**: same three demo CSVs, bundled as assets.

## Delivery

- CI: `dart test` for hisab_core + `flutter build appbundle` (debug
  signing on CI; release signing local) + asset-drift check.
- Local: release AAB with an upload keystore (Play App Signing);
  emulator screenshots via `adb exec-out screencap` with demo data.
- Play: closed-testing track upload, 12-tester/14-day clock, then
  production (per docs/playstore/checklist.md).

## Out of scope (v1)

Flutter-on-iOS release; PhonePe (still sample-blocked); any cloud
feature. Store-review posture is unchanged from the checklist: no data
collected, no financial features, nominative bank names only.
