# Flutter Android Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full-parity Flutter Android port of Hisab: pure-Dart `hisab_core` mirroring the Swift core with byte-identical content hashes, all 9 format parsers + the generic bank engine, drift storage, five screens, release AAB + emulator screenshots.

**Architecture:** See spec `docs/superpowers/specs/2026-09-17-flutter-android-design.md`. The Swift sources in `HisabCore/Sources/HisabCore/` and app code in `Hisab/` are the executable specification — every Dart module is a semantic port of its named Swift counterpart, and every Dart test suite ports the Swift suite's cases. This plan therefore specifies *invariants and interfaces* per task and names the Swift source of truth, rather than repeating implementations.

**Tech Stack:** Flutter 3.41 / Dart 3, packages: crypto, archive, xml, syncfusion_flutter_pdf, drift + sqlite3_flutter_libs, fl_chart, file_picker, url_launcher, path_provider. NO networking packages.

**Spec:** docs/superpowers/specs/2026-09-17-flutter-android-design.md

## Global Constraints

- Dart core work happens in `hisab_flutter/packages/hisab_core`; run `dart test` there after every task (no CPU gate needed — it's light; `flutter build` steps DO gate: `J=$(~/.claude/scripts/cpu-gate.sh)`).
- The six pinned hashes in `HisabCore/Tests/HisabCoreTests/SourceMigrationTests.swift` are law; the Dart pin test must assert the identical hex strings.
- Fixtures and bundled JSON are synced from HisabCore by `tool/sync_assets.sh`, never hand-copied or edited on the Dart side.
- All calendar math in fixed IST (+05:30); money is integer paise.
- Zero network: no dep may transitively require network permission; AndroidManifest gets NO INTERNET permission (the mailto intent needs none).
- Commit at every task boundary on branch `feat/flutter-android`; never push to main.
- Real statements live in gitignored `samples/`; the real-sample harness is tagged `@Tags(['samples'])` and skipped when the directory is missing (CI).

---

### Task F1: Scaffold + asset sync
- [ ] `flutter create --org com.vedants --project-name hisab hisab_flutter` (Android only artifacts kept; ios/ left but untouched); create `hisab_flutter/packages/hisab_core` via `dart create -t package`; wire path dependency; set `applicationId com.vedants.hisab`.
- [ ] `tool/sync_assets.sh`: copies HisabCore `Resources/formats/*.json` + `Resources/rulesets/*.json` → `hisab_flutter/assets/...` AND `HisabCore/Tests/HisabCoreTests/Fixtures/*` → `hisab_flutter/packages/hisab_core/test/fixtures/`; `--check` mode diffs (for CI). Run it.
- [ ] Remove INTERNET permission if present in AndroidManifest; `flutter analyze` clean. Commit.

### Task F2: Core primitives + hash parity (year_month, money, domain, content_hash, dedup)
Port from YearMonth.swift, Money.swift, Domain.swift, ContentHash.swift, Dedup.swift. Interfaces: `YearMonth(year, month)` with `months(from,through)`, IST helpers; `Money.formatPaise(int, {signed})`, `Money.signedPaise(String) -> int?`; `Source` value class with frozen ids + `builtIn` + `kind`/`displayName`/`ordered`; `ParsedTransaction.contentHash(Source)`; `Dedup.newIndices`.
- [ ] Port tests first from YearMonthTests/MoneyTests/ContentHashTests/DedupTests + **the pin test with the exact six hex digests from SourceMigrationTests.swift** (`532f81e5…`, `10f9d2d9…`, `241b83db…`, `962aaa86…`, `219b6e97…`, refless `a756f6fc…`) and the open-id expectations (bank:sbi → kind bank, displayName "SBI"; JSON encodes as bare string).
- [ ] Implement; `dart test` green. Commit `feat(flutter): core primitives with cross-platform hash parity`.

### Task F3: Domain engines (coverage, categories+ruleset, reconciliation, self_transfers, analytics, suggestion_engine)
Port from Coverage.swift, Categories.swift, Reconciliation.swift, SelfTransfers.swift, Analytics.swift, SuggestionEngine.swift with their test suites (CoverageTests, CategorizerTests, ReconciliationTests, SelfTransferTests, AnalyticsTests, SuggestionEngineTests). Ruleset loads india-default.json from the package's synced copy (test) / app asset (runtime) via an injected loader.
- [ ] Tests ported → fail; implement → green; commit.

### Task F4: Generic bank engine
Port GenericBank/: NormalizedTable (csv/txt adapters + xlsx via archive+xml + xls via MinimalXLS port; PDF adapter arrives in F6), SyntheticRef, ChainInterpreter (+ColumnMapping incl. referencePatterns + two-pass opening direction + openingBalance), FormatSpec/SpecExecutor (incl. detectPatterns)/SpecStore, ColumnInference (conservative), FormatFingerprint (+privacy property + mailtoURL to vedantsaboo2001@gmail.com), ImportResolver (parsers→specs→inference→unsupported/unverified; slugify). Port test suites: NormalizedTableTests, SyntheticRefTests, ChainInterpreterTests, SpecExecutorTests, SpecParityTests (IDFC XLSX spec vs code parser hashes), ColumnInferenceTests, FormatFingerprintTests, BundledSpecTests (all 9 specs × own fixture, no cross-detection), ImportResolverTests.
- [ ] MinimalXLS port validated by the hdfc-fixture.xls test; MinimalZip is replaced by `archive`.
- [ ] Tests → implement → green; commit per module group (≥3 commits).

### Task F5: Non-PDF code parsers
Port SyntheticCSVParser, PaytmXLSXParser, IDFCXLSXParser, HDFCTXTParser, HDFCXLSParser (+ their tests incl. cross-format hash-equality where fixtures allow). StatementParser interface mirrors Swift (`source`, `canParse(bytes, filename)`, `parse(bytes, password)`).
- [ ] Tests → implement → green; commit.

### Task F6: PDF extraction + PDF parsers + real-sample validation
- [ ] `PdfTextLines` adapter over syncfusion_flutter_pdf: page → ordered lines (y-sorted, x-grouped words) + per-line bounds; password unlock; also feeds NormalizedTable's pdf branch.
- [ ] Port GPayPDFParser, PaytmPDFParser, BHIMPDFParser, IDFCPDFParser, HDFCPDFParser — adapt line-assembly to Syncfusion ordering; geometric HDFC uses word bounds (port of the rect-selection approach).
- [ ] Real-sample harness `test/samples_test.dart` (tag `samples`): for each real file in `../../../samples/**`, parse and assert the exact counts/sums recorded in `samples/README.md` (GPay 295; Paytm 39 both formats hash-identical; IDFC 161 both; HDFC 451 PDF / 310 TXT+XLS hash-identical; BHIM per README) and cross-format hash-set equality. Iterate until to-the-paisa green locally.
- [ ] Commit per parser.

### Task F7: Storage + services (drift, import, queries, demo)
- [ ] drift schema mirroring StoredModels.swift (+UNIQUE contentHash, uuid keys, categoryOverride, sortOrder, monthKey); ImportService port (file sha256 dup-check → resolver → dedup insert → recomputeMatches); Queries port (rules seeding additive-merge, visible/analytics/grid/suggestionRecords/effectiveCategory/recomputeMatches); DemoData from bundled demo CSVs; KeychainHelper → `flutter_secure_storage`? NO — avoid extra dep: passwords stored via drift table is unacceptable (plaintext) → use `flutter_secure_storage` (no network) as the one platform dep. Unit-test services with drift's NativeDatabase.memory().
- [ ] Commit.

### Task F8: UI — theme + five screens + flows
- [ ] theme.dart (palette tokens, amount text style, source glyphs via Material icons), main.dart (tabs, launch seeding, --dart-define debug hooks for demo seed), Dashboard (hero card w/ bankVerified, fl_chart trend, coverage strip, recon health, category bars, merchants, recent), Buckets (dynamic columns + pin months + document sheet), Transactions (filters w/ active badge + clear, category chip editing, txn detail), Reconciliation, Settings (load demo, erase, rules editor incl. tap-to-edit), ImportSheet flow (file_picker, password field w/ secure-storage recall, report view, FormatRequestSheet w/ mailto), SuggestionPrompt (≤1/IST-day, mute list in shared_preferences).
- [ ] `flutter analyze` clean; widget smoke test for each screen with in-memory db + demo data. Commit per screen group.

### Task F9: Release plumbing + screenshots + CI + docs
- [ ] Upload keystore (`~/keys/hisab-upload.jks`, gitignored path documented), signingConfig release; `J=$(cpu-gate)`; `flutter build appbundle --release` succeeds.
- [ ] Emulator: create/boot AVD, install release apk variant, seed demo, capture ≥4 phone screenshots (1080×2400) via `adb exec-out screencap` → `docs/playstore/screenshots/`.
- [ ] CI: `.github/workflows/ci.yml` gains a `flutter` job (ubuntu: sync-assets --check, dart test, flutter build appbundle --debug).
- [ ] README: Android section + Play badge placeholder; docs/playstore/checklist.md updated (what's now unblocked). Commit; open PR to main.

## Final verification
- [ ] `dart test` (all, minus samples tag on CI) green; local samples-tagged run green to the paisa.
- [ ] Swift suite still green (`swift test` — untouched but prove it).
- [ ] AAB builds release; app runs on emulator with demo data end-to-end (import demo → dashboard → buckets → txns → recon → settings).
