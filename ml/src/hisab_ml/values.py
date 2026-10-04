"""Random surface forms for every slot. Each generator returns the text as it
would appear in an alert; the gold field value is recovered from that text by
`normalize`, so a renderer and a normalizer can never silently disagree
(tests/test_generate.py checks the round trip on every slot)."""

from __future__ import annotations

import random
from datetime import date, timedelta

FIRST = """Rahul Priya Amit Sneha Vikram Anjali Arjun Kavya Rohan Pooja Sanjay Neha
Aditya Divya Karan Meera Suresh Lakshmi Ramesh Deepa Manoj Swati Nikhil Ritu
Harish Bhavana Ganesh Shalini Vivek Nandini Imran Fatima Joseph Mary Gurpreet
Harpreet Arvind Sunita Mohan Geeta Pranav Ishita Siddharth Aishwarya Venkat
Padma Rajesh Usha Abdul Ayesha Farhan Zoya Tenzin Lalit Kiran Varun Tanvi
Yash Riya Dinesh Kamala Prakash Revathi Anil Sarita Ravi Madhuri Omkar Jyoti""".split()

LAST = """Sharma Verma Gupta Iyer Nair Reddy Patel Shah Mehta Joshi Kulkarni Desai
Rao Menon Pillai Singh Kaur Gill Khan Shaikh Ansari Das Bose Banerjee Mukherjee
Chatterjee Ghosh Sen Mishra Tiwari Pandey Yadav Chauhan Rathore Agarwal Jain
Bansal Goyal Saxena Srivastava Naidu Hegde Shetty Fernandes DSouza Thomas
Varghese Kurian Bhat Kamath Pawar Jadhav Shinde More Chavan Saboo Malhotra
Kapoor Khanna Arora Bhatia Sethi Chopra Ahuja""".split()

MERCHANTS = """SWIGGY|Zomato|AMAZON PAY INDIA|Amazon|FLIPKART|Myntra|BigBasket|BLINKIT|
Zepto|DMart|Reliance Fresh|Reliance Digital|Croma|Uber India|OLA|Rapido|IRCTC|
MakeMyTrip|Goibibo|BookMyShow|Netflix|Spotify|Hotstar|JioCinema|Airtel|Jio Prepaid|
Vodafone Idea|Tata Power|BESCOM|MSEDCL|Adani Electricity|Mahanagar Gas|Indane Gas|
HP PETROL PUMP|Indian Oil|Bharat Petroleum|Apollo Pharmacy|MedPlus|Practo|
Cult.fit|Decathlon|IKEA|Lenskart|Nykaa|Tanishq|Starbucks|Third Wave Coffee|
BLUE TOKAI COFFEE|Chaayos|Haldirams|McDonalds|Dominos Pizza|KFC|Burger King|
Paradise Biryani|Barbeque Nation|PVR INOX|Urban Company|Dunzo|Swiggy Instamart|
LIC of India|HDFC Life|Groww|Zerodha|Upstox|CRED|Google Play|Apple Services|
YouTube Premium|Microsoft|ACT Fibernet|Tata Play|Zoomcar|FASTag Recharge|
Indian Clearing Corporation|BSE Limited|CAMS|KFintech|Star Health|ICICI Lombard""".replace("\n", "").split("|")

FUNDS = """HDFC Flexi Cap Fund(G)|Parag Parikh Flexi Cap Fund-Reg(G)|Axis Bluechip Fund-Growth|
Mirae Asset Large Cap Fund-Reg-G|SBI Small Cap Fund-Reg-Growth|ICICI Pru Nifty 50 Index Fund|
Nippon India Small Cap Fund (G)|Kotak Emerging Equity Fund-Reg-G|UTI Nifty 50 Index Fund-Growth|
Quant Active Fund-Growth|Motilal Oswal Midcap Fund-Reg(G)|DSP ELSS Tax Saver Fund-Reg-G""".replace("\n", "").split("|")

AMCS = ["HDFCMF", "Axis MF", "SBI MF", "ICICI Prudential MF", "Mirae Asset MF", "Nippon India MF",
        "PPFAS MF", "Kotak MF", "CAMS", "KFintech"]

SHOP_KIND = """KIRANA STORE|GENERAL STORES|MEDICALS|SWEETS|BAKERY|TEA STALL|
FRUITS AND VEGETABLES|ELECTRICALS|HARDWARE|TAILORS|DAIRY|CHICKEN CENTRE|
STATIONERY|MOBILE SHOP|SALON|DHABA|PAAN SHOP|LAUNDRY|AUTO WORKS""".replace("\n", "").split("|")

SHOP_PREFIX = "SHREE|SRI|NEW|JAI|OM SAI|LAXMI|BALAJI|GANESH|ANNAPURNA|MAA|ROYAL|CITY".split("|")

HANDLES = """okaxis okhdfcbank okicici oksbi ybl ibl axl paytm ptyes ptsbi pthdfc upi
apl yapl axisbank hdfcbank icici sbi kotak idfcbank fbpe axb naviaxis superyes
jupiteraxis fam waicici""".split()

ISSUERS = {
    # display name used in sign-offs -> NEFT/RTGS IFSC prefix
    "HDFC Bank": "HDFC", "ICICI Bank": "ICIC", "SBI": "SBIN", "Axis Bank": "UTIB",
    "Kotak Mahindra Bank": "KKBK", "IDFC FIRST Bank": "IDFB", "Yes Bank": "YESB",
    "IndusInd Bank": "INDB", "Punjab National Bank": "PUNB", "Bank of Baroda": "BARB",
    "Canara Bank": "CNRB", "Union Bank of India": "UBIN", "Federal Bank": "FDRL",
    "AU Small Finance Bank": "AUBL", "RBL Bank": "RATN", "IDBI Bank": "IBKL",
    "Bank of India": "BKID", "Indian Bank": "IDIB", "Paytm Payments Bank": "PYTM",
    "Airtel Payments Bank": "AIRP",
}

TODAY = date(2026, 9, 30)


def amount(rng: random.Random) -> str:
    # Mostly small UPI spends, a long tail of salary/rent-sized movements.
    r = rng.random()
    if r < 0.55:
        v = rng.randint(10, 2_000) * 100 + rng.choice([0, 0, 0, 50, rng.randint(1, 99)])
    elif r < 0.9:
        v = rng.randint(2_000, 60_000) * 100 + rng.choice([0, 0, rng.randint(1, 99)])
    else:
        v = rng.randint(60_000, 9_00_000) * 100
    return format_paise(v, rng)


def format_paise(v: int, rng: random.Random) -> str:
    rupees, paise = divmod(v, 100)
    style = rng.random()
    if style < 0.35:
        whole = _indian_group(rupees)
    elif style < 0.5:
        whole = f"{rupees:,}"
    else:
        whole = str(rupees)
    if paise == 0 and rng.random() < 0.35:
        return whole
    return f"{whole}.{paise:02d}"


def _indian_group(n: int) -> str:
    s = str(n)
    if len(s) <= 3:
        return s
    head, tail = s[:-3], s[-3:]
    groups = []
    while len(head) > 2:
        groups.insert(0, head[-2:])
        head = head[:-2]
    if head:
        groups.insert(0, head)
    return ",".join(groups + [tail])


def currency(rng: random.Random) -> str:
    return rng.choice(["Rs.", "Rs. ", "Rs ", "INR ", "INR", "₹", "₹ ", "Rs.", "INR "])


def txn_date(rng: random.Random) -> date:
    return TODAY - timedelta(days=rng.randint(0, 400))


def date_text(rng: random.Random) -> str:
    d = txn_date(rng)
    fmt = rng.choice([
        "%d-%m-%y", "%d-%m-%Y", "%d/%m/%y", "%d/%m/%Y", "%d-%b-%y", "%d-%b-%Y",
        "%d%b%y", "%d %b %Y", "%Y-%m-%d", "%d.%m.%Y", "%d-%b-%Y", "%b %d, %Y",
        "%d-%m",  # year-less, as HDFC's older alerts write it
    ])
    s = d.strftime(fmt)
    return s.upper() if rng.random() < 0.3 else s


def time_text(rng: random.Random) -> str:
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    return rng.choice([f"{h:02d}:{m:02d}:{s:02d}", f"{h:02d}:{m:02d}",
                       f"{(h % 12) or 12:02d}:{m:02d} {'AM' if h < 12 else 'PM'}"])


def acct(rng: random.Random) -> str:
    digits = "".join(rng.choice("0123456789") for _ in range(rng.choice([4, 4, 4, 3])))
    mask = rng.choice(["XX", "XX", "XXXXXXXX", "XXXXXX", "xx", "*", "**", "X", "XXXXXXXXXXX"])
    return mask + digits


def card(rng: random.Random) -> str:
    digits = "".join(rng.choice("0123456789") for _ in range(4))
    return rng.choice(["XX", "xx", "*", "XXXX", "", "XXXX XXXX XXXX "]) + digits


def rrn(rng: random.Random) -> str:
    return str(rng.randint(2, 6)) + "".join(rng.choice("0123456789") for _ in range(11))


def neft_utr(rng: random.Random, ifsc: str) -> str:
    digits = lambda n: "".join(rng.choice("0123456789") for _ in range(n))
    r = rng.random()
    if r < 0.15:
        return "N" + digits(15)                                  # no bank code
    if r < 0.3:
        return ifsc + digits(4) + rng.choice("ABCDEFGHJKLMNPQRSTUVWXYZ") + digits(7)  # IDFB6220M8743447
    return ifsc + rng.choice("NH") + digits(11)


def rtgs_utr(rng: random.Random, ifsc: str) -> str:
    return ifsc + "R" + rng.choice("0123456789") + "".join(rng.choice("0123456789") for _ in range(16))


def person(rng: random.Random) -> str:
    first, last = rng.choice(FIRST), rng.choice(LAST)
    style = rng.random()
    if style < 0.4:
        s = f"{first} {last}".upper()
    elif style < 0.7:
        s = f"{first} {last}"
    elif style < 0.85:
        s = f"{first.upper()} {last[0]}"
    else:
        s = first.upper()
    if rng.random() < 0.12:
        s = rng.choice(["Mr ", "Ms ", "Mrs ", "Dr ", "MR ", "Shri "]) + s
    return s


def merchant(rng: random.Random) -> str:
    if rng.random() < 0.7:
        m = rng.choice(MERCHANTS)
        return m.upper() if rng.random() < 0.4 else m
    owner = rng.choice([rng.choice(SHOP_PREFIX), rng.choice(LAST).upper()])
    return f"{owner} {rng.choice(SHOP_KIND)}"


def payee(rng: random.Random) -> str:
    return person(rng) if rng.random() < 0.5 else merchant(rng)


def vpa(rng: random.Random) -> str:
    first, last = rng.choice(FIRST).lower(), rng.choice(LAST).lower()
    local = rng.choice([
        f"{first}.{last}", f"{first}{last}{rng.randint(1, 99)}", f"{first}{rng.randint(10, 9999)}",
        str(rng.randint(6_000_000_000, 9_999_999_999)),
        f"paytmqr{rng.randint(10**9, 10**10 - 1)}", f"q{rng.randint(10**8, 10**9 - 1)}",
        f"bharatpe.{rng.randint(10**9, 10**10 - 1)}", f"{rng.choice(MERCHANTS).split()[0].lower().strip('.')}.payments",
    ])
    return f"{local}@{rng.choice(HANDLES)}"


def helpline(rng: random.Random) -> str:
    return rng.choice(["18002586161", "1800-103-8181", "18601207777", "1800 425 3800",
                       "18002026161", "1860-266-2666", "18004195959"])


def otp(rng: random.Random) -> str:
    return "".join(rng.choice("0123456789") for _ in range(rng.choice([4, 6, 6])))


def user_name(rng: random.Random) -> str:
    return rng.choice(["Customer", rng.choice(FIRST), rng.choice(FIRST).upper(),
                       f"{rng.choice(FIRST)} {rng.choice(LAST)}"])
