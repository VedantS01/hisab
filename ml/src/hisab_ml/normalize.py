"""Span text -> field value. Strict on purpose: a span that does not normalize
is treated as absent, never repaired. The app-side verifier ports these
rules to Swift and Dart, so keep them small and free of heuristics."""

from __future__ import annotations

import re
import string

# ASCII-only on purpose: Python, Swift and Dart disagree on Unicode case
# mapping (İ, ß, final sigma) and on what counts as whitespace, and every value
# normalized here is ASCII anyway. The ports implement exactly these helpers.
WS = " \t\n\r\x0b\x0c"
_WS_RUN = re.compile("[" + WS + "]+")
_LOWER = str.maketrans(string.ascii_uppercase, string.ascii_lowercase)
_UPPER = str.maketrans(string.ascii_lowercase, string.ascii_uppercase)


def lower(s: str) -> str:
    return s.translate(_LOWER)


def upper(s: str) -> str:
    return s.translate(_UPPER)


def trim(s: str) -> str:
    return s.strip(WS)

# Plain digits, Indian grouping (1,23,456) or Western grouping (123,456);
# a grouped number always ends in a 3-digit group.
_AMOUNT = re.compile(r"^(?:\d+|\d{1,2}(?:,\d{2})*,\d{3}|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$", re.A)
_TAIL = re.compile(r"(\d{3,})$", re.A)
_REF_PATTERNS = (
    re.compile(r"^\d{12}$", re.A),           # UPI RRN / IMPS ref
    # NEFT/RTGS UTR: bank code + 12 or 18 alphanumerics. Real UTRs carry
    # letters mid-string (IDFB6220M8743447) and HDFC uses 22 characters for
    # NEFT too, so neither the tail nor the length pins the rail.
    re.compile(r"^[A-Z]{4}(?:[A-Z0-9]{12}|[A-Z0-9]{18})$", re.A),
    # Older NEFT UTRs carry no bank code: N244243236394874.
    re.compile(r"^[A-Z](?:\d{15}|\d{21})$", re.A),
)


def _digits(s: str) -> int:
    return sum("0" <= c <= "9" for c in s)


def amount_paise(text: str) -> int | None:
    s = trim(text).removesuffix("/-")
    if not _AMOUNT.match(s):
        return None
    rupees, _, frac = s.replace(",", "").partition(".")
    return int(rupees) * 100 + int((frac + "00")[:2])


def acct_tail(text: str) -> str | None:
    # Last 4 at most: one account shows as XX8816, XXXXXXX8816 and XXXXX308816
    # across alerts from the same bank, and they must normalize alike.
    m = _TAIL.search(trim(text))
    return m.group(1)[-4:] if m else None


def ref(text: str) -> str | None:
    s = upper(trim(text))
    # At least 8 digits: a reference is mostly number, never a word.
    return s if _digits(s) >= 8 and any(p.match(s) for p in _REF_PATTERNS) else None


_MONTHS = {m: i + 1 for i, m in enumerate("jan feb mar apr may jun jul aug sep oct nov dec".split())}
_FULL_MONTHS = {m: i + 1 for i, m in enumerate(
    "january february march april may june july august september october november december".split())}

# Tried in order, each a full match. Fields: d day, m month number, b month
# abbreviation, B full month name, y year (2 or 4 digits). This list is the
# portable spelling of the strptime formats the generator emits; the tests
# hold it equal to strptime on every format.
_DATE_PATTERNS = [
    (r"(\d{1,2})([-/.])(\d{1,2})\2(\d{2}|\d{4})", "d_m_y"),   # 22-09-26, 22/09/2026, 22.09.26
    (r"(\d{1,2})-([a-z]{3})-(\d{2}|\d{4})", "dby"),           # 22-Sep-26
    (r"(\d{1,2})([a-z]{3})(\d{2}|\d{4})", "dby"),             # 22Sep26
    (r"(\d{1,2}) ([a-z]{3}) (\d{2}|\d{4})", "dby"),           # 22 Sep 2026
    (r"(\d{1,2})([- ])([a-z]+)\2(\d{4})", "d_By"),            # 22-September-2026
    (r"([a-z]{3}) (\d{1,2}), (\d{4})", "bdy"),                # Sep 22, 2026
    (r"(\d{4})-(\d{1,2})-(\d{1,2})", "ymd"),                  # 2026-09-22
]
# No year: HDFC writes "14-08"; the app takes the year from when the alert arrived.
_YEARLESS_PATTERNS = [
    (r"(\d{1,2})-(\d{1,2})", "dm"), (r"(\d{1,2})/(\d{1,2})", "dm"), (r"(\d{1,2})-([a-z]{3})", "db"),
    (r"(\d{1,2}) ([a-z]{3})", "db"), (r"([a-z]{3}) (\d{1,2})", "bd"), (r"(\d{1,2})([a-z]{3})", "db"),
]
_DATE_RE = [(re.compile(p, re.I | re.A), k) for p, k in _DATE_PATTERNS]
_YEARLESS_RE = [(re.compile(p, re.I | re.A), k) for p, k in _YEARLESS_PATTERNS]


def _year(y: str) -> int:
    # strptime's %y pivot: 69-99 -> 19xx, 00-68 -> 20xx.
    n = int(y)
    return n if len(y) == 4 else (1900 + n if n >= 69 else 2000 + n)


def _ymd(kind: str, g: tuple[str, ...]) -> tuple[int, int, int] | None:
    """(year, month, day) from a match, or None if a month name is unknown.
    Yearless kinds use 2000, a leap year, so 29 Feb survives the check."""
    match kind:
        case "d_m_y":
            return _year(g[3]), int(g[2]), int(g[0])
        case "dby":
            m = _MONTHS.get(lower(g[1]))
            return (_year(g[2]), m, int(g[0])) if m else None
        case "d_By":
            m = _FULL_MONTHS.get(lower(g[2]))
            return (int(g[3]), m, int(g[0])) if m else None
        case "bdy":
            m = _MONTHS.get(lower(g[0]))
            return (int(g[2]), m, int(g[1])) if m else None
        case "ymd":
            return int(g[0]), int(g[1]), int(g[2])
        case "dm":
            return 2000, int(g[1]), int(g[0])
        case "db":
            m = _MONTHS.get(lower(g[1]))
            return (2000, m, int(g[0])) if m else None
        case "bd":
            m = _MONTHS.get(lower(g[0]))
            return (2000, m, int(g[1])) if m else None
    raise ValueError(kind)


def _valid(y: int, m: int, d: int) -> bool:
    if not (1 <= m <= 12 and d >= 1):
        return False
    leap = y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
    return d <= (31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[m - 1]


def date_iso(text: str) -> str | None:
    """ISO date, or `--MM-DD` when the alert names no year."""
    s = re.sub(r"(\d)(?:st|nd|rd|th)\b", r"\1", trim(text), flags=re.I | re.A)    # 31st -> 31
    s = trim(_WS_RUN.sub(" ", s.replace("'", " ")))                                  # Oct' 2024 -> Oct 2024
    for patterns, yearless in ((_DATE_RE, False), (_YEARLESS_RE, True)):
        for rx, kind in patterns:
            m = rx.fullmatch(s)
            ymd = _ymd(kind, m.groups()) if m else None
            if ymd and _valid(*ymd):
                y, mo, d = ymd
                return f"--{mo:02d}-{d:02d}" if yearless else f"{y:04d}-{mo:02d}-{d:02d}"
    return None


_HONORIFIC = re.compile(r"^(?:mr|mrs|ms|miss|dr|shri|smt|m/s)\.? +")


def name(text: str) -> str | None:
    s = lower(_WS_RUN.sub(" ", text).strip(" .,:;-"))
    return _HONORIFIC.sub("", s) or None
