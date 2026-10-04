"""Alert formats, written as templates.

DSL:
  {slot}          filler text from `values`, unlabeled
  {slot:LABEL}    filler text recorded as a span with that label
  [[a|b|]]        one alternative chosen at random (may be empty);
                  alternatives may contain slots, but do not nest

A template is a FORMAT, not a sample: the split holds whole templates out of
training, so the test set measures generalisation to layouts the model has
never seen — the property a format-agnostic parser has to have.

Wording follows the shape of real Indian bank, card, UPI-app and email alerts
(sender conventions, masking, reference styles). No real customer text is
reproduced here.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Template:
    id: str
    channel: str               # sms | notification | email
    is_txn: bool
    direction: str | None      # debit | credit | None for non-transactions
    text: str
    issuer: str | None = None  # fixed issuer for bank-specific layouts


def _t(id, channel, kind, text, issuer=None):
    is_txn = kind in ("debit", "credit")
    return Template(id, channel, is_txn, kind if is_txn else None, text, issuer)


D, C, X = "debit", "credit", "none"

TEMPLATES: list[Template] = [
    # ---------------- SMS: debits ----------------
    _t("sms_hdfc_sent", "sms", D,
       "Sent {cur}{amt:AMOUNT}\nFrom HDFC Bank A/C {acct:OWN_ACCT}\nTo {payee:PAYEE}\nOn {date:DATE}\n"
       "Ref {rrn:REF}\nNot You?\nCall {helpline}/SMS BLOCK UPI to 7308080808", "HDFC Bank"),
    _t("sms_hdfc_vpa", "sms", D,
       "{cur}{amt:AMOUNT} debited from a/c {acct:OWN_ACCT} on {date:DATE} to VPA {vpa:VPA}"
       "[[ ({payee:PAYEE})|]] (UPI Ref No {rrn:REF}). Not you? Call on {helpline} to report", "HDFC Bank"),
    _t("sms_sbi_upi", "sms", D,
       "Dear UPI user A/C {acct:OWN_ACCT} debited by {amt:AMOUNT} on date {date:DATE} trf to {payee:PAYEE} "
       "Refno {rrn:REF}. If not u? call 1800111109. -SBI", "SBI"),
    _t("sms_icici_upi", "sms", D,
       "ICICI Bank Acct {acct:OWN_ACCT} debited for Rs {amt:AMOUNT} on {date:DATE}; {payee:PAYEE} credited. "
       "UPI:{rrn:REF}. Call 18002662 for dispute. SMS BLOCK {tail} to 9215676766.", "ICICI Bank"),
    _t("sms_axis_upi", "sms", D,
       "INR {amt:AMOUNT} debited\nA/c no. {acct:OWN_ACCT}\n{date:DATE}, {time}\nUPI/[[P2A|P2M]]/{rrn:REF}/{payee:PAYEE}\n"
       "Not you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank", "Axis Bank"),
    _t("sms_kotak_sent", "sms", D,
       "Sent Rs.{amt:AMOUNT} from Kotak Bank AC {acct:OWN_ACCT} to {vpa:VPA} on {date:DATE}.UPI Ref {rrn:REF}. "
       "Not you, https://kotak.com/KBANKT/Fraud", "Kotak Mahindra Bank"),
    _t("sms_idfc_imps_pair", "sms", D,
       "Your a/c ending {acct:OWN_ACCT} is debited by Rs. {amt:AMOUNT} on {date:DATE} and a/c ending "
       "{acct:CPTY_ACCT} credited (IMPS Ref no {rrn:REF} ). Team IDFC FIRST Bank", "IDFC FIRST Bank"),
    _t("sms_idfc_upi", "sms", D,
       "Your A/C {acct:OWN_ACCT} is debited by INR {amt:AMOUNT} on {date:DATE} for UPI txn to {vpa:VPA}. "
       "UPI Ref {rrn:REF}. Avl Bal INR {bal:BALANCE}. If not done by you, call 18004194332-IDFC FIRST Bank",
       "IDFC FIRST Bank"),
    _t("sms_pnb_upi", "sms", D,
       "A/c {acct:OWN_ACCT} debited INR {amt:AMOUNT} Dt {date:DATE} {time} thru UPI:{rrn:REF}.Bal INR {bal:BALANCE} "
       "Not u?Fwd this SMS to 9264092640 to block UPI.-PNB", "Punjab National Bank"),
    _t("sms_bob_upi", "sms", D,
       "Rs.{amt:AMOUNT} transferred from A/c {acct:OWN_ACCT} to:UPI/{rrn:REF}. Total Bal:Rs.{bal}CR. "
       "Avlbl Amt:Rs.{bal:BALANCE}({date:DATE} {time}) - Bank of Baroda", "Bank of Baroda"),
    _t("sms_canara_upi", "sms", D,
       "An amount of INR {amt:AMOUNT} has been DEBITED to your account {acct:OWN_ACCT} on {date:DATE} towards "
       "UPI/{rrn:REF}/{payee:PAYEE}. Total Avail.Bal INR {bal:BALANCE}. - Canara Bank", "Canara Bank"),
    _t("sms_union_mob", "sms", D,
       "A/c {acct:OWN_ACCT} Debited for Rs:{amt:AMOUNT} on {date:DATE} by Mob Bk ref no {rrn:REF} Avl Bal "
       "Rs:{bal:BALANCE}.If not you, Call 1800222243 -Union Bank of India", "Union Bank of India"),
    _t("sms_cc_spent", "sms", D,
       "Spent {cur}{amt:AMOUNT} On {bank} Card {card:OWN_ACCT} At {merchant:PAYEE} On {date:DATE}:{time}\n"
       "Not You? To Block+Reissue, Call {helpline}"),
    _t("sms_icici_cc", "sms", D,
       "INR {amt:AMOUNT} spent using ICICI Bank Card {card:OWN_ACCT} on {date:DATE} on {merchant:PAYEE}. "
       "Avl Limit: INR {lim}. If not you, call 1800 2662/SMS BLOCK {tail} to 9215676766.", "ICICI Bank"),
    _t("sms_sbicard", "sms", D,
       "Rs.{amt:AMOUNT} spent on your SBI Credit Card ending {tail:OWN_ACCT} at {merchant:PAYEE} on {date:DATE}. "
       "Trxn. not done by you? Report at https://sbicard.com/Dispute", "SBI"),
    _t("sms_axis_cc", "sms", D,
       "Spent\nCard no. {card:OWN_ACCT}\nINR {amt:AMOUNT}\n{date:DATE} {time}\n{merchant:PAYEE}\nAvl Lmt INR {lim}\n"
       "SMS BLOCK {tail} to 919951860002, if not you - Axis Bank", "Axis Bank"),
    _t("sms_atm", "sms", D,
       "{cur}{amt:AMOUNT} withdrawn at ATM {atm} from A/c {acct:OWN_ACCT} on {date:DATE}[[ {time}|]]. "
       "Avl Bal {cur}{bal:BALANCE}. Not you? Call {helpline} -{bank}"),
    _t("sms_nach", "sms", D,
       "Rs {amt:AMOUNT} debited from A/c {acct:OWN_ACCT} on {date:DATE} towards NACH-{merchant:PAYEE}-{umrn}. "
       "Avl bal Rs {bal:BALANCE} -{bank}"),
    _t("sms_emi", "sms", D,
       "EMI of Rs.{amt:AMOUNT} for Loan A/c {loan:CPTY_ACCT} has been debited from your a/c {acct:OWN_ACCT} "
       "on {date:DATE}. -{bank}"),
    _t("sms_upi_mandate_exec", "sms", D,
       "Rs.{amt:AMOUNT} debited from A/c {acct:OWN_ACCT} for {merchant:PAYEE} UPI Mandate on {date:DATE}. "
       "UPI Ref {rrn:REF}. -{bank}"),
    _t("sms_neft_out", "sms", D,
       "Rs {amt:AMOUNT} has been debited from your A/c {acct:OWN_ACCT} on {date:DATE} towards NEFT to "
       "{person:PAYEE} A/c {acct:CPTY_ACCT}. UTR {neft:REF}. -{bank}"),
    _t("sms_rtgs_out", "sms", D,
       "RTGS of INR {amt:AMOUNT} from A/c {acct:OWN_ACCT} to {payee:PAYEE} processed on {date:DATE}. "
       "UTR No: {rtgs:REF}. Avl Bal INR {bal:BALANCE}"),
    _t("sms_imps_out", "sms", D,
       "IMPS of Rs {amt:AMOUNT} from A/c {acct:OWN_ACCT} to A/c {acct:CPTY_ACCT} ({person:PAYEE}) successful. "
       "Ref {rrn:REF}. {date:DATE} {time} -{bank}"),
    _t("sms_debitcard_pos", "sms", D,
       "Your {bank} Debit Card {card:OWN_ACCT} was used for Rs.{amt:AMOUNT} at {merchant:PAYEE} on {date:DATE} "
       "{time}. Avl Bal: Rs.{bal:BALANCE}"),
    _t("sms_purchase", "sms", D,
       "Purchase of INR {amt:AMOUNT} made on {bank} Debit card {card:OWN_ACCT} at {merchant:PAYEE} on {date:DATE}."
       "[[ Not you? Call {helpline}|]]"),
    _t("sms_paytm_bank", "sms", D,
       "Paid Rs.{amt:AMOUNT} to {payee:PAYEE} from Paytm Payments Bank a/c {acct:OWN_ACCT}. UPI Ref:{rrn:REF}. "
       "Bal Rs.{bal:BALANCE}", "Paytm Payments Bank"),
    _t("sms_charges", "sms", D,
       "Rs.{amt:AMOUNT} debited from A/c {acct:OWN_ACCT} on {date:DATE} towards [[SMS Charges|Annual Debit Card "
       "Fee|Min Bal Charges]]. Avl Bal Rs {bal:BALANCE} -{bank}"),
    _t("sms_fastag", "sms", D,
       "Rs.{amt:AMOUNT} has been debited from your FASTag wallet linked to vehicle {vehicle} at {toll:PAYEE} on "
       "{date:DATE} {time}. Avl Bal Rs.{bal:BALANCE}"),
    _t("sms_generic_upi_debit", "sms", D,
       "Dear Customer, {cur}{amt:AMOUNT} [[debited|deducted|paid]] from your {bank} account {acct:OWN_ACCT} "
       "[[to|towards]] {payee:PAYEE} on {date:DATE}. [[UPI Ref|Ref No|RRN]] {rrn:REF}."),

    # ---------------- SMS: credits ----------------
    _t("sms_hdfc_received", "sms", C,
       "[[Money Received - |]]INR {amt:AMOUNT} in your A/c {acct:OWN_ACCT} on {date:DATE} from VPA {vpa:VPA}"
       "[[ ({person:PAYEE})|]] (UPI Ref No {rrn:REF})", "HDFC Bank"),
    _t("sms_sbi_credit", "sms", C,
       "Dear SBI User, your A/c {acct:OWN_ACCT}-credited by Rs.{amt:AMOUNT} on {date:DATE} transfer from "
       "{person:PAYEE} Ref No {rrn:REF} -SBI", "SBI"),
    _t("sms_icici_credit", "sms", C,
       "Dear Customer, Acct {acct:OWN_ACCT} is credited with Rs {amt:AMOUNT} on {date:DATE} from {payee:PAYEE}. "
       "UPI:{rrn:REF}-ICICI Bank.", "ICICI Bank"),
    _t("sms_salary_neft", "sms", C,
       "INR {amt:AMOUNT} credited to your A/c {acct:OWN_ACCT} on {date:DATE} by NEFT from {employer:PAYEE} "
       "UTR {neft:REF}. Avl Bal INR {bal:BALANCE} -{bank}"),
    _t("sms_imps_in", "sms", C,
       "IMPS credit of Rs.{amt:AMOUNT} received in A/c {acct:OWN_ACCT} from A/c {acct:CPTY_ACCT} on {date:DATE}. "
       "Ref No {rrn:REF} -{bank}"),
    _t("sms_refund", "sms", C,
       "Refund of Rs.{amt:AMOUNT} from {merchant:PAYEE} has been credited to your A/c {acct:OWN_ACCT} on "
       "{date:DATE}. Ref {rrn:REF}"),
    _t("sms_reversal", "sms", C,
       "Rs.{amt:AMOUNT} reversed to your A/c {acct:OWN_ACCT} on {date:DATE} for failed UPI txn Ref {rrn:REF}. -{bank}"),
    _t("sms_interest", "sms", C,
       "Interest of Rs {amt:AMOUNT} credited to A/c {acct:OWN_ACCT} on {date:DATE}. Avl Bal Rs {bal:BALANCE} -{bank}"),
    _t("sms_cashback_credit", "sms", C,
       "Cashback of Rs.{amt:AMOUNT} credited to your {bank} account {acct:OWN_ACCT} for txn at {merchant:PAYEE}."),
    _t("sms_rtgs_in", "sms", C,
       "Your A/c {acct:OWN_ACCT} is credited with INR {amt:AMOUNT} on {date:DATE} via RTGS from {payee:PAYEE}. "
       "UTR {rtgs:REF}. -{bank}"),
    _t("sms_kotak_received", "sms", C,
       "Received Rs.{amt:AMOUNT} in your Kotak Bank AC {acct:OWN_ACCT} from {vpa:VPA} on {date:DATE}."
       "UPI Ref:{rrn:REF}.", "Kotak Mahindra Bank"),
    _t("sms_cheque_credit", "sms", C,
       "Your A/c {acct:OWN_ACCT} credited with Rs.{amt:AMOUNT} on {date:DATE} by Clg Chq {chq}. "
       "Bal Rs {bal:BALANCE} -{bank}"),
    _t("sms_idfc_imps_pair_in", "sms", C,
       "Your a/c ending {acct:OWN_ACCT} is credited by Rs. {amt:AMOUNT} on {date:DATE} from a/c ending "
       "{acct:CPTY_ACCT} (IMPS Ref no {rrn:REF} ). Team IDFC FIRST Bank", "IDFC FIRST Bank"),
    _t("sms_cc_payment_received", "sms", C,
       "Payment of Rs {amt:AMOUNT} received towards your {bank} Credit Card {card:OWN_ACCT} on {date:DATE}. Thank you."),
    _t("sms_generic_credit", "sms", C,
       "{cur}{amt:AMOUNT} [[credited to|deposited in|added to]] your a/c {acct:OWN_ACCT} [[by|from]] "
       "{payee:PAYEE} on {date:DATE}[[. Ref {rrn:REF}|]]. -{bank}"),

    # ---------------- notifications ----------------
    _t("ntf_gpay_paid", "notification", D, "{cur}{amt:AMOUNT} paid to {payee:PAYEE}\n{bank} ••{tail:OWN_ACCT}"),
    _t("ntf_gpay_received", "notification", C, "{person:PAYEE} paid you {cur}{amt:AMOUNT}"),
    _t("ntf_phonepe_paid", "notification", D,
       "Paid {cur}{amt:AMOUNT} to {payee:PAYEE}[[\nUPI Ref ID: {rrn:REF}|]]"),
    _t("ntf_phonepe_received", "notification", C, "Received {cur}{amt:AMOUNT} from {person:PAYEE}"),
    _t("ntf_paytm_paid", "notification", D,
       "Paid Rs.{amt:AMOUNT} to {payee:PAYEE}\nFrom: {bank} - {tail:OWN_ACCT}"),
    _t("ntf_cred", "notification", D, "payment of {cur}{amt:AMOUNT} to {merchant:PAYEE} successful"),
    _t("ntf_bank_debit", "notification", D,
       "Debit Alert\nINR {amt:AMOUNT} debited from A/c {acct:OWN_ACCT} for UPI/{rrn:REF}/{payee:PAYEE}"),
    _t("ntf_bank_credit", "notification", C,
       "Credit Alert\nINR {amt:AMOUNT} credited to A/c {acct:OWN_ACCT} by {payee:PAYEE}"),
    _t("ntf_bhim", "notification", D,
       "Transaction successful. {cur}{amt:AMOUNT} sent to {vpa:VPA}. Txn ID: {rrn:REF}"),
    _t("ntf_amazonpay", "notification", D, "Payment of {cur}{amt:AMOUNT} to {merchant:PAYEE} was successful"),
    _t("ntf_card_txn", "notification", D,
       "{bank}\nTransaction of {cur}{amt:AMOUNT} at {merchant:PAYEE} on your card {card:OWN_ACCT}"),
    _t("ntf_wallet_added", "notification", C,
       "{cur}{amt:AMOUNT} added to your wallet from {bank} a/c {acct:OWN_ACCT}"),

    # ---------------- email ----------------
    _t("eml_hdfc_upi", "email", D,
       "Dear Customer,\n\n{cur}{amt:AMOUNT} has been debited from account {acct:OWN_ACCT} to VPA {vpa:VPA} "
       "[[{payee:PAYEE} |]]on {date:DATE}.\n\nYour UPI transaction reference number is {rrn:REF}.\n\n"
       "If you did not authorize this transaction, please report it immediately by calling {helpline}.\n\n"
       "Warm Regards,\nHDFC Bank", "HDFC Bank"),
    _t("eml_icici_cc", "email", D,
       "Dear {user},\n\nYour ICICI Bank Credit Card {card:OWN_ACCT} has been used for a transaction of INR "
       "{amt:AMOUNT} on {date:DATE} at {time}. Info: {merchant:PAYEE}.\n\nThe Available Credit Limit on your card "
       "is INR {lim} and Total Credit Limit is INR {lim}.\n\nSincerely,\nICICI Bank", "ICICI Bank"),
    _t("eml_axis_debit", "email", D,
       "Dear {user},\n\nThank you for banking with us.\n\nWe wish to inform you that INR {amt:AMOUNT} has been "
       "debited from your A/c no. {acct:OWN_ACCT} on {date:DATE} at {time} IST by UPI/P2M/{rrn:REF}/"
       "{merchant:PAYEE}.\n\nAlways open to help you.\n\nRegards,\nAxis Bank Ltd.", "Axis Bank"),
    _t("eml_salary", "email", C,
       "Dear {user},\n\nYour account {acct:OWN_ACCT} has been credited with INR {amt:AMOUNT} on {date:DATE} by NEFT "
       "from {employer:PAYEE}. UTR: {neft:REF}.\n\nAvailable balance: INR {bal:BALANCE}\n\nRegards,\n{bank}"),
    _t("eml_sbi_transfer", "email", D,
       "Dear Customer,\n\nYour A/C {acct:OWN_ACCT} has a debit by transfer of Rs {amt:AMOUNT} on {date:DATE}. "
       "Avl Bal Rs {bal:BALANCE}.\n\nThis is a system generated mail. -State Bank of India", "SBI"),
    _t("eml_imps_out", "email", D,
       "Dear {user},\n\nIMPS Transaction Successful\n\nAmount: INR {amt:AMOUNT}\nFrom Account: {acct:OWN_ACCT}\n"
       "Beneficiary: {person:PAYEE}\nBeneficiary Account: {acct:CPTY_ACCT}\nIMPS Reference No: {rrn:REF}\n"
       "Date: {date:DATE}\n\nRegards,\n{bank}"),
    _t("eml_card_receipt", "email", D,
       "Hi {user},\n\nThanks for using your {bank} Debit Card ending {tail:OWN_ACCT}.\nMerchant: {merchant:PAYEE}\n"
       "Amount: {cur}{amt:AMOUNT}\nDate: {date:DATE} {time}\n\nTeam {bank}"),
    _t("eml_refund", "email", C,
       "Dear {user},\n\nWe have processed a refund of {cur}{amt:AMOUNT} from {merchant:PAYEE} to your account "
       "{acct:OWN_ACCT} on {date:DATE}. Reference: {rrn:REF}.\n\nRegards,\n{bank}"),

    # ---------------- not transactions ----------------
    _t("x_otp_card", "sms", X,
       "{otp} is your OTP for txn of {cur}{amt} at {merchant} on your {bank} card {card}. Valid for 10 mins. "
       "Do not share it with anyone."),
    _t("x_otp_upi", "sms", X,
       "Do not share OTP {otp} for adding your {bank} A/c {acct} to a UPI app. Bank never asks for OTP."),
    _t("x_promo_cashback", "sms", X,
       "Get flat {cur}{amt} cashback on your first UPI payment with {merchant}! T&C apply. bit.ly/3xYz"),
    _t("x_promo_loan", "sms", X,
       "Dear {user}, you are pre-approved for a Personal Loan of Rs.{amt} at 10.5% p.a. Disbursal in 10 mins. "
       "Apply now -{bank}"),
    _t("x_failed_upi", "sms", X,
       "Your UPI txn of Rs.{amt} to {vpa} has FAILED. Ref {rrn}. Amount, if debited, will be refunded in 3 "
       "working days. -{bank}"),
    _t("x_declined", "sms", X,
       "Txn of INR {amt} on your {bank} Card {card} at {merchant} declined due to [[insufficient balance|incorrect "
       "PIN|exceeded limit]]."),
    _t("x_upcoming_debit", "sms", X,
       "Your A/c {acct} will be debited with Rs.{amt} on {date} towards {merchant} mandate. Maintain sufficient "
       "balance. -{bank}"),
    _t("x_cc_statement", "sms", X,
       "Your {bank} Credit Card {card} statement is generated. Total Amount Due: Rs.{amt}. Min Due: Rs.{amt}. "
       "Due Date: {date}."),
    _t("x_collect_request", "sms", X,
       "{person} has requested Rs.{amt} from you on [[Google Pay|PhonePe|Paytm|BHIM]]. Approve only if you know the "
       "sender. Never enter UPI PIN to receive money."),
    _t("x_balance", "sms", X,
       "Avl Bal in your A/c {acct} as on {date} is Rs.{bal}. -{bank}"),
    _t("x_mandate_setup", "sms", X,
       "UPI AutoPay mandate of up to Rs.{amt} created for {merchant}. UMN: {umrn}. -{bank}"),
    _t("x_bill_due", "sms", X,
       "Your {merchant} bill of Rs.{amt} is due on {date}. Pay now to avoid late fee."),
    _t("x_kyc", "sms", X, "Dear {user}, your KYC is due for update. Please visit your nearest branch. -{bank}"),
    _t("x_cashback_pending", "notification", X,
       "Cashback of {cur}{amt} will be credited within 3 days for your payment to {merchant}"),
    _t("x_ntf_request", "notification", X, "{person} requested {cur}{amt}"),
    _t("x_ntf_failed", "notification", X, "Payment of {cur}{amt} to {payee} failed. Any amount debited will be refunded."),
    _t("x_emi_due", "sms", X,
       "EMI of Rs.{amt} for Loan A/c {loan} is due on {date}. Please keep sufficient balance in A/c {acct}. -{bank}"),
    _t("x_eml_statement", "email", X,
       "Dear {user},\n\nYour account statement for the period ending {date} is attached. The PDF is password "
       "protected.\n\nClosing balance: INR {bal}\n\nRegards,\n{bank}"),
    _t("x_eml_offer", "email", X,
       "Hi {user},\n\nShop on {merchant} with your {bank} card and get up to {cur}{amt} off.\n\nOffer valid till "
       "{date}. T&C apply.\n\nTeam {bank}"),
]
