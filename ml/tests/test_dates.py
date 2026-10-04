"""normalize.date_iso is the portable spelling of a strptime parser. Hold it
equal to strptime itself, used here only as an independent oracle."""

import json
import re
from datetime import date, datetime, timedelta
from pathlib import Path

import pytest

from hisab_ml.normalize import date_iso

FORMATS = ("%d-%m-%y", "%d-%m-%Y", "%d/%m/%y", "%d/%m/%Y", "%d.%m.%y", "%d.%m.%Y", "%d-%b-%y", "%d-%b-%Y",
           "%d%b%y", "%d%b%Y", "%d %b %y", "%d %b %Y", "%d-%B-%Y", "%d %B %Y", "%b %d, %Y", "%Y-%m-%d")
YEARLESS = ("%d-%m", "%d/%m", "%d-%b", "%d %b", "%b %d", "%d%b")


def oracle(text: str) -> str | None:
    s = re.sub(r"(\d)(?:st|nd|rd|th)\b", r"\1", text.strip(), flags=re.I | re.A)
    s = re.sub(r"\s+", " ", s.replace("'", " ")).strip()
    for fmt in FORMATS:
        try:
            return datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            pass
    for fmt in YEARLESS:
        try:
            d = datetime.strptime(f"{s} 2000", f"{fmt} %Y")
            return f"--{d.month:02d}-{d.day:02d}"
        except ValueError:
            pass
    return None


def _grid():
    days = [date(1969, 1, 1), date(1999, 12, 31), date(2000, 2, 29), date(2024, 2, 29), date(2068, 7, 4)]
    d = date(2024, 1, 1)
    while d < date(2027, 1, 1):
        days.append(d)
        d += timedelta(days=17)
    for d in days:
        for fmt in FORMATS + YEARLESS:
            s = d.strftime(fmt)
            yield s
            yield s.upper()
            yield s.lower()
            yield re.sub(r"\b0(\d)", r"\1", s)        # unpadded day / month


def test_matches_strptime_on_every_format():
    bad = [(s, date_iso(s), oracle(s)) for s in _grid() if date_iso(s) != oracle(s)]
    assert not bad, bad[:10]


@pytest.mark.parametrize("s", ["31-02-26", "29-02-25", "00-01-26", "13/13/26", "22-Sepx-26", "Sept 22, 2026",
                               "22-09/26", "2026-9-22", "22 Sep, 2026", "31st Oct' 2024", "1st Jan", "14-08",
                               "450.00", "", "2026", "22SEP2026", "22-SEPTEMBER-2026", "22 september 2026"])
def test_matches_strptime_on_edge_cases(s):
    assert date_iso(s) == oracle(s)


def test_matches_strptime_on_real_labels():
    path = Path("data/real/real-train.jsonl")
    if not path.exists():
        pytest.skip("private real labels not present")
    spans = [r["text"][s["start"]:s["end"]] for line in path.read_text().splitlines()
             for r in [json.loads(line)] for s in r["spans"] if s["label"] == "DATE"]
    assert spans
    bad = [(s, date_iso(s), oracle(s)) for s in spans if date_iso(s) != oracle(s)]
    assert not bad, bad[:10]
