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
    re.compile(r"^[A-Z]{4}[A-Z0-9]\d{11}$"), # NEFT UTR, 16 chars
    re.compile(r"^[A-Z]{4}R[A-Z0-9]\d{16}$"),# RTGS UTR, 22 chars
)
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
    return s if any(p.match(s) for p in _REF_PATTERNS) else None


def date_iso(text: str) -> str | None:
    s = text.strip()
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            continue
    return None


_HONORIFIC = re.compile(r"^(?:mr|mrs|ms|miss|dr|shri|smt|m/s)\.?\s+")


def name(text: str) -> str | None:
    s = re.sub(r"\s+", " ", text).strip(" .,:;-").lower()
    return _HONORIFIC.sub("", s) or None
