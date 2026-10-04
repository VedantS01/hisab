"""Compositional alerts: clauses assembled at random instead of fixed templates.

Hand-written templates teach the model template identity: v2 learned
"mandate" => not a transaction and missed "Payment ... processed successfully
... e-mandate". Here every alert is built from interchangeable parts — opener,
core clause, counterparty, date, reference, balance, footer — in varied order,
and the core clause carries the meaning: a debit verb, a credit verb, or a
status that cancels the movement (failed, pending, scheduled, initiated). The
only way to fit this data is to read those words.

Output is template-DSL text (see templates.py), rendered by generate.render,
so slots and spans come from the same tested path. Compositional records are
training-only; held-out hand templates and real alerts stay the test.
"""

from __future__ import annotations

import random
import re

from .templates import Template

AMOUNT = ["{cur}{amt:AMOUNT}", "INR {amt:AMOUNT}", "Rs. {amt:AMOUNT}", "Rs.{amt:AMOUNT}", "INR.{amt:AMOUNT}",
          "an amount of {cur}{amt:AMOUNT}", "Rs {amt:AMOUNT}"]
OWN = ["[[your |]][[a/c|A/c|A/C|account|Acct|A/c no.|A/C No|account no.]] {acct:OWN_ACCT}",
       "[[your |]][[a/c|account]] ending {acct:OWN_ACCT}",
       "{bank} [[A/c|A/C|account|Bank A/c]] {acct:OWN_ACCT}",
       "[[your |]]{bank} [[Credit|Debit]] Card [[ending |no. |]]{card:OWN_ACCT}",
       "[[your |]]Savings A/c {acct:OWN_ACCT}"]

DEBIT_CORE = [
    "{amount} [[has been |is |was |]][[debited|deducted|withdrawn|transferred|charged]] from {own}",
    "{own} [[has been |is |]]debited [[by|for|with]] {amount}",
    "[[Sent|Paid|Spent|Transferred]] {amount}[[ from {own}|]]",
    "You [[have |]][[paid|sent|spent|transferred]] {amount}[[ from {own}|]]",
    "[[Your |]]Payment of {amount} [[made|done|was successful|processed successfully|is successful]]"
    "[[ from {own}| using {own}|]]",
    "Purchase of {amount} [[made |]]on {own}",
    "{own} [[was |has been |]]used for {amount}",
    "[[Debit Alert|DEBIT|Money Sent|Payment Successful]][[!|:|]] {amount}[[ from {own}|]]",
    "{amount} spent [[on|using]] {own}",
    "Withdrawal of {amount} from {own}",
]
DEBIT_PARTY = [" to {payee:PAYEE}", " to VPA {vpa:VPA}", " towards {merchant:PAYEE}", " at {merchant:PAYEE}",
               "; {payee:PAYEE} credited", " to A/c {acct:CPTY_ACCT}[[ ({person:PAYEE})|]]",
               " for {merchant:PAYEE}", ". Info: [[UPI|ACH D-|POS|NACH]]/{merchant:PAYEE}",
               " to {payee:PAYEE} ({vpa:VPA})", "\nTo {payee:PAYEE}", " to beneficiary {person:PAYEE}"]

CREDIT_CORE = [
    "{amount} [[has been |is |was |]][[credited|deposited|added|refunded|reversed]] [[to|in|into]] {own}",
    "{own} [[has been |is |]]credited [[by|with|for]] {amount}",
    "[[Received|Money received|You received|You have received]] {amount}[[ in {own}|]]",
    "Refund of {amount} [[has been credited|credited|processed and credited]][[ to {own}|]]",
    "Payment of {amount} [[received|has been received]] towards {own}",
    "[[Credit Alert|CREDIT|Money Received|Amount Credited]][[!|:|]] {amount}[[ in {own}| to {own}|]]",
    "Deposit of {amount} [[made |]]in {own}",
    "{amount} received in {own}",
]
CREDIT_PARTY = [" from {payee:PAYEE}", " from VPA {vpa:VPA}", " by {payee:PAYEE}", " from A/c {acct:CPTY_ACCT}",
                " by NEFT from {employer:PAYEE}", "; {payee:PAYEE} debited", ". Info: [[NEFT|IMPS|UPI]]/{payee:PAYEE}",
                "\nFrom {payee:PAYEE}", " sent by {person:PAYEE}", " for IMPS -{person:PAYEE}-"]
# Self-contained cores that already name the counterparty.
CREDIT_SELF = ["{person:PAYEE} [[paid|sent]] you {amount}", "{payee:PAYEE} has [[sent|transferred]] {amount} to {own}"]
DEBIT_SELF = ["{amount} paid to {payee:PAYEE}", "Paid {amount} to {payee:PAYEE}",
              "Your SIP of {amount} in {fund:PAYEE} [[has been processed|is processed]] at NAV {nav}",
              "Your payment of {amount} to {merchant:PAYEE} was successful"]

# Same surface material, no completed movement: these must come out "none".
NONE_CORE = [
    "[[Your |]][[payment|transaction|UPI txn|transfer|IMPS transfer|NEFT]] of {amountx}[[ to {payee}| at {merchant}|]]"
    " [[has failed|failed|was declined|is declined|is pending|is PENDING|could not be processed|was unsuccessful|"
    "has been rejected|is on hold]]",
    "{amountx} [[will be|is scheduled to be|shall be|is due to be]] [[debited|deducted|charged|auto-debited]]"
    "[[ from {ownx}|]][[ on {date}| for {merchant}|]]",
    "Refund of {amountx} [[has been initiated|is initiated|is being processed|will be credited]][[ for {merchant}|]]",
    "Cashback of {amountx} will be credited[[ in 3 days| shortly|]]",
    "{person} has requested {amountx}[[ from you|]]",
    "[[OTP|One Time Password]] {otp} for [[txn|transaction|payment]] of {amountx}[[ at {merchant}|]]."
    " [[Do not share|Never share it with anyone]]",
    "[[Available|Avl]] balance in {ownx} [[is|as on {date} is]] {cur}{bal}",
    "Your SIP of {amountx} in {fund} [[is due on {date}|will be debited on {date}|is registered]]",
    "Your [[bill|EMI|premium|dues]] of {amountx} is due on {date}",
    "Pre-approved [[loan|credit limit]] of {amountx} [[is ready|available]] for you",
    "Mandate of up to {amountx} [[created|registered|set up]] for {merchant}",
    "Total amount due {amountx}. Minimum due {cur}{amt}. Pay by {date}",
    "Your order of {amountx} from {merchant} [[has been placed|is confirmed]]",
]
AMOUNT_X = ["{cur}{amt}", "INR {amt}", "Rs. {amt}", "Rs.{amt}", "Rs {amt}"]
OWN_X = ["[[your |]][[a/c|A/c|account]] {acct}", "{bank} A/c {acct}", "[[your |]]{bank} Card {card}"]

OPENER = ["", "", "", "Dear Customer, ", "Dear {user}, ", "Alert: ", "Txn Alert: ", "UPDATE: ", "{bank}: ",
          "Transaction Alert\n", "Hi {user},\n", "[[Important|Info]]: "]
DATE = [" on {date:DATE}", " on {date:DATE} at {time}", " Dt {date:DATE}", "\nOn {date:DATE}",
        " ({date:DATE} {time})", " on {date:DATE} {time}", "\n{date:DATE}"]
REF_UPI = ["[[UPI Ref|UPI Ref No|Ref No|Ref|RRN|IMPS Ref no|Txn ID|UPI|Reference No]][[:| |: | No. ]]{rrn:REF}"]
REF_NEFT = ["[[UTR|UTR No|NEFT Ref|Ref]][[:| |: ]]{neft:REF}", "Info: NEFT/{neft:REF}"]
BALANCE = ["[[Avl Bal|Avl bal|Available balance|New Bal|Bal|Total Avail.Bal|Your new balance is|New A/C balance is]]"
           "[[:| |: | :]][[{cur}|INR |Rs.|Rs ]]{bal:BALANCE}"]
FOOTER = ["", "", "Not you? Call {helpline}", "-{bank}", "Team {bank}", "If not done by you, call {helpline}.",
          "SMS BLOCK to 9215676766 if not you", "- {bank}", "Never share OTP/PIN with anyone. -{bank}"]
SEP = [". ", ". ", "\n", " ", ", ", ".\n"]


_CHOICE = re.compile(r"\[\[(.*?)\]\]", re.S)


def _pick(options: list[str], rng: random.Random) -> str:
    # Resolve a piece's own [[...]] before it is placed inside another choice:
    # the template DSL does not nest.
    return _CHOICE.sub(lambda m: rng.choice(m.group(1).split("|")), rng.choice(options))


def _fill(core: str, rng: random.Random) -> str:
    return (core.replace("{amount}", _pick(AMOUNT, rng)).replace("{own}", _pick(OWN, rng))
            .replace("{amountx}", _pick(AMOUNT_X, rng)).replace("{ownx}", _pick(OWN_X, rng)))


def compose(rng: random.Random) -> Template:
    r = rng.random()
    kind = "debit" if r < 0.42 else "credit" if r < 0.72 else "none"
    clauses: list[str] = []
    if kind == "none":
        clauses.append(_fill(rng.choice(NONE_CORE), rng))
        # Distractors with real-looking references keep "has a ref" from
        # meaning "is a transaction".
        if rng.random() < 0.4:
            clauses.append(rng.choice(["Ref {rrn}", "UPI Ref No {rrn}", "Order {order}", "UMN {umn}"]))
    else:
        if rng.random() < 0.15:
            core = rng.choice(DEBIT_SELF if kind == "debit" else CREDIT_SELF)
            clauses.append(_fill(core, rng))
        else:
            core = rng.choice(DEBIT_CORE if kind == "debit" else CREDIT_CORE)
            party = rng.choice(DEBIT_PARTY if kind == "debit" else CREDIT_PARTY) if rng.random() < 0.75 else ""
            clauses.append(_fill(core, rng) + party)
        if rng.random() < 0.8:
            clauses[-1] += rng.choice(DATE)
        if rng.random() < 0.6:
            clauses.append(rng.choice(REF_NEFT if rng.random() < 0.15 else REF_UPI))
        if rng.random() < 0.35:
            clauses.append(rng.choice(BALANCE))
        if rng.random() < 0.15:
            clauses.append(rng.choice(["UMRN: {umrn}", "Order {order}", "Folio {folio}"]))
        # Clause order varies, but the core clause stays first in most alerts.
        if len(clauses) > 2 and rng.random() < 0.3:
            rest = clauses[1:]
            rng.shuffle(rest)
            clauses = clauses[:1] + rest
    text = rng.choice(OPENER)
    for i, c in enumerate(clauses):
        text += c if i == 0 else rng.choice(SEP) + c
    footer = rng.choice(FOOTER)
    if footer:
        text += rng.choice(SEP) + footer
    is_txn = kind != "none"
    channel = rng.choice(["sms", "sms", "notification", "email"])
    return Template(id="compose", channel=channel, is_txn=is_txn, direction=kind if is_txn else None, text=text)
