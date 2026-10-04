"""Span text -> field value. Strict on purpose: a span that does not normalize
is treated as absent, never repaired. The app-side verifier ports these
rules to Swift and Dart, so keep them small and free of heuristics."""

from __future__ import annotations

import re
from datetime import datetime

# Plain digits, Indian grouping (1,23,456) or Western grouping (123,456);
# a grouped number always ends in a 3-digit group.
_AMOUNT = re.compile(r"^(?:\d+|\d{1,2}(?:,\d{2})*,\d{3}|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$")
_TAIL = re.compile(r"(\d{3,})$")
_REF_PATTERNS = (
    re.compile(r"^\d{12}$"),                 # UPI RRN / IMPS ref
    # NEFT/RTGS UTR: bank code + 12 or 18 alphanumerics. Real UTRs carry
    # letters mid-string (IDFB6220M8743447) and HDFC uses 22 characters for
    # NEFT too, so neither the tail nor the length pins the rail.
    re.compile(r"^[A-Z]{4}(?:[A-Z0-9]{12}|[A-Z0-9]{18})$"),
    # Older NEFT UTRs carry no bank code: N244243236394874.
    re.compile(r"^[A-Z](?:\d{15}|\d{21})$"),
)


def _digits(s: str) -> int:
    return sum(c.isdigit() for c in s)
_DATE_FORMATS = (
    "%d-%m-%y", "%d-%m-%Y", "%d/%m/%y", "%d/%m/%Y", "%d.%m.%y", "%d.%m.%Y",
    "%d-%b-%y", "%d-%b-%Y", "%d%b%y", "%d%b%Y", "%d %b %y", "%d %b %Y",
    "%d-%B-%Y", "%d %B %Y", "%b %d, %Y", "%Y-%m-%d",
)


def amount_paise(text: str) -> int | None:
    s = text.strip().removesuffix("/-")
    if not _AMOUNT.match(s):
        return None
    rupees, _, frac = s.replace(",", "").partition(".")
    return int(rupees) * 100 + int((frac + "00")[:2])


def acct_tail(text: str) -> str | None:
    # Last 4 at most: one account shows as XX8816, XXXXXXX8816 and XXXXX308816
    # across alerts from the same bank, and they must normalize alike.
    m = _TAIL.search(text.strip())
    return m.group(1)[-4:] if m else None


def ref(text: str) -> str | None:
    s = text.strip().upper()
    # At least 8 digits: a reference is mostly number, never a word.
    return s if _digits(s) >= 8 and any(p.match(s) for p in _REF_PATTERNS) else None


_YEARLESS_FORMATS = ("%d-%m", "%d/%m", "%d-%b", "%d %b", "%b %d", "%d%b")


def date_iso(text: str) -> str | None:
    """ISO date, or `--MM-DD` when the alert names no year (HDFC writes
    "14-08"); the app takes the year from when the alert arrived."""
    s = re.sub(r"(\d)(?:st|nd|rd|th)\b", r"\1", text.strip(), flags=re.I)   # 31st -> 31
    s = re.sub(r"\s+", " ", s.replace("'", " ")).strip()                    # Oct' 2024 -> Oct 2024
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            continue
    for fmt in _YEARLESS_FORMATS:
        try:
            # A leap year, so 29 Feb parses.
            d = datetime.strptime(f"{s} 2000", f"{fmt} %Y")
            return f"--{d.month:02d}-{d.day:02d}"
        except ValueError:
            continue
    return None


_HONORIFIC = re.compile(r"^(?:mr|mrs|ms|miss|dr|shri|smt|m/s)\.?\s+")


def name(text: str) -> str | None:
    s = re.sub(r"\s+", " ", text).strip(" .,:;-").lower()
    return _HONORIFIC.sub("", s) or None
