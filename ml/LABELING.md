# Labelling real alerts

Each message gets a `kind` and `labels`. Labels are substrings; the checker
(`python -m hisab_ml.realdata check <file>`) rejects anything that is not.

## kind

- **debit**: the message confirms money has LEFT one of the user's accounts,
  cards or wallets: a completed payment, transfer, withdrawal, purchase,
  SIP/MF investment, bill or EMI payment, fee or charge.
- **credit**: the message confirms money has ARRIVED in one of the user's
  accounts, cards or wallets: received, credited, refund credited, interest,
  salary, reversal of a debit, card bill payment received.
- **none**: nothing has moved, or not yet:
  - OTPs, promotions and offers, loan offers, KYC and service messages
  - failed, declined, pending or on-hold payments
  - future or scheduled debits: "will be debited", pre-debit and e-mandate
    notices, upcoming autopay, bill or EMI due reminders
  - collect requests and payment links
  - balance-only messages, statement-generated notices
  - refunds *initiated* but not yet credited; cashback that "will be credited"
  - orders placed with no payment confirmation; mandates created or set up

Any sender counts: banks, card issuers, UPI apps, wallets, merchants, payment
gateways, mutual funds, insurers. What matters is whether the message confirms
a completed movement of the user's money. Two messages for the same payment
from different senders are fine, because the app de-duplicates by reference.

## labels

Copy the value EXACTLY as written: case, commas and decimals. If the first
occurrence of the string is not the one you mean, write `["string", n]` for
its n-th occurrence (1-based). Include only the labels that are present.
A `none` message has `"labels": {}`.

| Label | What | Examples |
|---|---|---|
| AMOUNT | transaction amount; number only, no currency or `/-` | `1,23,456.78`, `5000.00`, `980` |
| REF | payment-rail reference ONLY: UPI RRN/UPI Ref/IMPS ref (12 digits), NEFT/RTGS UTR | `626523840940`, `HDFCH01294551929` |
| OWN_ACCT | the user's account, card or wallet as written, mask included | `XX3293`, `*3293`, `XXXXX308816`, `3293`, `0787` |
| CPTY_ACCT | the other party's account as written | `XXXXXXXXXXX293` |
| PAYEE | counterparty name as written: who was paid (debit), who paid (credit); merchant, person, company, fund | `MUNCHMART TECHNOLOGIES PR`, `Mr MO ALAM` |
| VPA | counterparty UPI id | `8498954794@axl` |
| DATE | the transaction's date as written, date part only | `04/10/26`, `25-SEP-26`, `2025-11-06` |
| BALANCE | available/new account balance after the transaction; number only | `35,585.86` |

**Never REF:** order IDs, gateway payment IDs (`pay_...`), UMRN/UMN/mandate
IDs, SiHubId, cheque numbers, folio numbers, card authorisation codes,
transaction IDs that are not 12-digit RRNs or UTRs, phone numbers, OTPs.

**Never BALANCE:** credit limits ("Avl Lmt", "Available Credit Limit").

A value may not cut through a longer number or word. For example, the last 12
digits of `HDFC7020902210002459` are not a ref.

If you are unsure, still label the message, and add `"uncertain": true` with a
short `"note"`.

## output

`data/real/labels/batch-NN.json`: a JSON list with one entry per message in
`data/real/batches/batch-NN.jsonl`, in order:

```json
[{"id": "m00012", "kind": "debit", "labels": {"AMOUNT": "239.00", "OWN_ACCT": "*3293",
  "PAYEE": "MUNCHMART TECHNOLOGIES PR", "DATE": "04/10/26", "REF": "627775786529"}},
 {"id": "m00013", "kind": "none", "labels": {}}]
```
