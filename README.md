# Hisab (हिसाब)

A private, on-device iOS app for personal expense analysis. Import
Google Pay / Paytm transaction exports and HDFC / IDFC bank statements;
Hisab parses them deterministically, organizes everything into monthly
time buckets, cross-checks payment-app records against bank statements,
and shows a dashboard of where the money went.

- **On-device only** — SwiftUI + SwiftData, no server, no accounts.
- **HisabCore** — a pure-Swift, fully unit-tested package holding all
  parsing, dedup, bucketing, reconciliation, and analytics logic.
- **Bahi-khata design language** — the UI borrows its palette from the
  traditional red-cloth Indian ledger.

Design spec: [`docs/superpowers/specs/2026-09-05-hisab-design.md`](docs/superpowers/specs/2026-09-05-hisab-design.md)

> Personal-format parsers: this app targets the exact export formats of
> one user's accounts. Real statements live in the gitignored
> `samples/`; tests run on synthetic fixtures only.
