#!/usr/bin/env python3
"""Generates synthetic bank-statement CSV fixtures, one per bundled FormatSpec.

Every fixture is invented data whose running balance closes to the paisa by
construction. Never replace these with real statements.
Run from this directory: python3 gen_bank_fixtures.py
"""
from decimal import Decimal

# (delta_rupees, narration) — negative = debit. 12 rows per fixture.
MOVEMENTS = [
    (Decimal("-542.50"), "POS COFFEE ROASTERY"),
    (Decimal("35000.00"), "SALARY FICTIONAL LABS"),
    (Decimal("-1200.00"), "UPI GROCER FRESHMART"),
    (Decimal("-89.00"), "UPI TEA STALL"),
    (Decimal("-4999.00"), "POS ELECTRONICS HUB"),
    (Decimal("2500.00"), "REFUND ELECTRONICS HUB"),
    (Decimal("-15000.00"), "RENT APRIL FLAT 4B"),
    (Decimal("-349.00"), "SUBSCRIPTION STREAMCO"),
    (Decimal("-2750.25"), "UPI RESTAURANT DINEWELL"),
    (Decimal("1000.00"), "CASHBACK PROMO"),
    (Decimal("-620.75"), "FUEL STATION CITYGAS"),
    (Decimal("-4500.00"), "INSURANCE PREMIUM SAFECO"),
]
OPEN = Decimal("100000.00")

DATES_DMY_SLASH = [f"{d:02d}/04/2026" for d in range(1, 13)]
DATES_DMY_DASH = [f"{d:02d}-04-2026" for d in range(1, 13)]
DATES_D_MMM = [f"{d:02d} Apr 2026" for d in range(1, 13)]

def rows(fmt_dates):
    bal = OPEN
    out = []
    for (delta, narr), date in zip(MOVEMENTS, fmt_dates):
        bal += delta
        out.append((date, narr, delta, bal))
    return out

def money(d):
    return f"{d:.2f}"

def write(name, lines):
    with open(name, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", name)

def debit_credit(name, furniture, header, fmt_dates, ref_prefix=None, extra_cols=None,
                 mid_furniture=None):
    lines = list(furniture) + [",".join(header)]
    for i, (date, narr, delta, bal) in enumerate(rows(fmt_dates), 1):
        debit = money(-delta) if delta < 0 else ""
        credit = money(delta) if delta > 0 else ""
        cells = [date]
        if header[1].lower().startswith("chq"):     # axis-classic: Chq No second
            cells += [f"CHQ{i:03d}" if ref_prefix else "", narr, debit, credit, money(bal)]
        else:
            cells.append(narr)
            if ref_prefix:
                cells.append(f"{ref_prefix}{i:06d}")
            cells += [debit, credit, money(bal)]
        if extra_cols:
            cells += extra_cols
        lines.append(",".join(cells))
        if mid_furniture and i == 6:
            lines.append(mid_furniture)
    write(name, lines)

# SBI: Txn Date | Value Date | Description | Ref No./Cheque No. | Debit | Credit | Balance
sbi_lines = ["STATE BANK OF INDIA", "Statement of Account",
             "Txn Date,Value Date,Description,Ref No./Cheque No.,Debit,Credit,Balance"]
for i, (date, narr, delta, bal) in enumerate(rows(DATES_D_MMM), 1):
    debit = money(-delta) if delta < 0 else ""
    credit = money(delta) if delta > 0 else ""
    sbi_lines.append(",".join([date, date, narr, f"SBIN{i:06d}", debit, credit, money(bal)]))
    if i == 6:
        sbi_lines.append("Statement of Account contd.")
write("sbi-table-fixture.csv", sbi_lines)

# ICICI classic: Value Date | Transaction Date | Cheque Number | Transaction Remarks |
#                Withdrawal Amount (INR) | Deposit Amount (INR) | Balance (INR)
icici_lines = ["ICICI BANK LIMITED",
               "Value Date,Transaction Date,Cheque Number,Transaction Remarks,"
               "Withdrawal Amount (INR),Deposit Amount (INR),Balance (INR)"]
for i, (date, narr, delta, bal) in enumerate(rows(DATES_DMY_SLASH), 1):
    debit = money(-delta) if delta < 0 else ""
    credit = money(delta) if delta > 0 else ""
    icici_lines.append(",".join([date, date, f"ICI{i:05d}", narr, debit, credit, money(bal)]))
write("icici-classic-fixture.csv", icici_lines)

# ICICI signed: Date | Narration | Ref/Cheque No | Amount | Balance
signed_lines = ["ICICI BANK LIMITED", "Date,Narration,Ref/Cheque No,Amount,Balance"]
for i, (date, narr, delta, bal) in enumerate(rows(DATES_DMY_SLASH), 1):
    signed_lines.append(",".join([date, narr, f"REF{i:05d}", money(delta), money(bal)]))
write("icici-signed-fixture.csv", signed_lines)

# Axis classic: Tran Date | Chq No | Particulars | Debit | Credit | Balance | Init.Br
axis_lines = ["AXIS BANK LTD", "Tran Date,Chq No,Particulars,Debit,Credit,Balance,Init.Br"]
for i, (date, narr, delta, bal) in enumerate(rows(DATES_DMY_DASH), 1):
    debit = money(-delta) if delta < 0 else ""
    credit = money(delta) if delta > 0 else ""
    axis_lines.append(",".join([date, f"CHQ{i:03d}", narr, debit, credit, money(bal), "BLR"]))
write("axis-classic-fixture.csv", axis_lines)

# Axis DR/CR: Tran Date | Particulars | Amount(INR) | DR/CR | Balance
drcr_lines = ["AXIS BANK LTD", "Tran Date,Particulars,Amount(INR),DR/CR,Balance"]
for date, narr, delta, bal in rows(DATES_DMY_DASH):
    drcr_lines.append(",".join([date, narr, money(abs(delta)),
                                "DR" if delta < 0 else "CR", money(bal)]))
write("axis-drcr-fixture.csv", drcr_lines)

# Kotak: Date | Narration | Chq/Ref No | Withdrawal Amt | Deposit Amt | Balance
kotak_lines = ["KOTAK MAHINDRA BANK", "Date,Narration,Chq/Ref No,Withdrawal Amt,Deposit Amt,Balance"]
for i, (date, narr, delta, bal) in enumerate(rows(DATES_DMY_SLASH), 1):
    debit = money(-delta) if delta < 0 else ""
    credit = money(delta) if delta > 0 else ""
    kotak_lines.append(",".join([date, narr, f"KKBK{i:05d}", debit, credit, money(bal)]))
write("kotak-table-fixture.csv", kotak_lines)

# PNB / BoB (provisional): Date | Particulars | Withdrawal | Deposit | Balance
for bank, name in [("PUNJAB NATIONAL BANK", "pnb-table-fixture.csv"),
                   ("BANK OF BARODA", "bob-table-fixture.csv")]:
    lines = [bank, "Date,Particulars,Withdrawal,Deposit,Balance"]
    for date, narr, delta, bal in rows(DATES_DMY_SLASH):
        debit = money(-delta) if delta < 0 else ""
        credit = money(delta) if delta > 0 else ""
        lines.append(",".join([date, narr, debit, credit, money(bal)]))
    write(name, lines)
