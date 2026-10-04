import random

import pytest

from hisab_ml import normalize
from hisab_ml.evaluate import score
from hisab_ml.generate import make_record, render, split_templates
from hisab_ml.schema import LABELS, Fields, Record
from hisab_ml.templates import TEMPLATES

NORMALIZERS = {
    "AMOUNT": normalize.amount_paise, "BALANCE": normalize.amount_paise, "REF": normalize.ref,
    "OWN_ACCT": normalize.acct_tail, "CPTY_ACCT": normalize.acct_tail, "DATE": normalize.date_iso,
    "PAYEE": normalize.name,
}


@pytest.mark.parametrize("t", TEMPLATES, ids=lambda t: t.id)
def test_every_span_normalizes(t):
    # A renderer emitting text its normalizer rejects would silently become a
    # gold "None" — the round trip must hold for every slot of every template.
    rng = random.Random(t.id)
    for i in range(200):
        r = make_record(t, i, rng)
        for s in r.spans:
            assert s.label in LABELS
            piece = r.text[s.start:s.end]
            assert piece and piece == piece.strip(), (piece, r.text)
            if s.label in NORMALIZERS:
                assert NORMALIZERS[s.label](piece) is not None, (s.label, piece, r.text)


@pytest.mark.parametrize("t", TEMPLATES, ids=lambda t: t.id)
def test_template_contract(t):
    rng = random.Random(0)
    _, spans, _ = render(t, rng)
    labels = {s.label for s in spans}
    if t.is_txn:
        assert t.direction in ("debit", "credit")
        assert "AMOUNT" in labels
    else:
        assert t.direction is None and not spans


def test_compose_records_are_well_formed():
    from hisab_ml.compose import compose

    rng = random.Random(11)
    kinds = set()
    for i in range(3000):
        r = make_record(compose(rng), i, rng)
        kinds.add(r.fields.direction)
        assert "[[" not in r.text and "{" not in r.text, r.text
        if r.fields.is_txn:
            assert r.fields.amount_paise, r.text
        else:
            assert not r.spans
        for s in r.spans:
            piece = r.text[s.start:s.end]
            assert piece == piece.strip() and piece
            if s.label in NORMALIZERS:
                assert NORMALIZERS[s.label](piece) is not None, (s.label, piece, r.text)
    assert kinds == {"debit", "credit", None}


def test_ids_unique_and_split_covers_each_kind():
    assert len({t.id for t in TEMPLATES}) == len(TEMPLATES)
    held = split_templates(TEMPLATES)
    kinds = {(t.is_txn, t.direction) for t in TEMPLATES if t.id in held}
    assert kinds == {(True, "debit"), (True, "credit"), (False, None)}
    assert 0.15 < len(held) / len(TEMPLATES) < 0.35


@pytest.mark.parametrize("text,paise", [
    ("450", 45000), ("450.5", 45050), ("1,23,456.78", 12345678), ("1,234.00", 123400),
    ("30000.00", 3000000), ("500/-", 50000), ("12,34", None), ("4.567", None), ("", None),
])
def test_amount(text, paise):
    assert normalize.amount_paise(text) == paise


@pytest.mark.parametrize("text,iso", [
    ("22-Sep-26", "2026-09-22"), ("22SEP26", "2026-09-22"), ("22/09/2026", "2026-09-22"),
    ("2026-09-22", "2026-09-22"), ("SEP 22, 2026", "2026-09-22"), ("31-02-26", None),
])
def test_date(text, iso):
    assert normalize.date_iso(text) == iso


@pytest.mark.parametrize("text,tail", [
    ("XX8816", "8816"), ("XXXXXXX8816", "8816"), ("XXXXX308816", "8816"), ("XXXXXXXX816", "816"),
    ("*3293", "3293"), ("3293", "3293"), ("XX12", None),
])
def test_acct_tail(text, tail):
    assert normalize.acct_tail(text) == tail


def test_ref_shapes():
    assert normalize.ref("626523840940") == "626523840940"
    assert normalize.ref("hdfcn52026092212") == "HDFCN52026092212"
    assert normalize.ref("HDFCR520260922123456789") is None  # 23 chars
    assert normalize.ref("12345") is None


def test_idfc_pair_labels_both_accounts():
    t = next(t for t in TEMPLATES if t.id == "sms_idfc_imps_pair")
    r = make_record(t, 0, random.Random(3))
    assert r.fields.direction == "debit"
    assert r.fields.own_acct_tail and r.fields.cpty_acct_tail
    assert "debited" in r.text.lower() and "credited" in r.text.lower()


def _rec(id, fields):
    return Record(id=id, text="", spans=[], fields=fields, channel="sms", template_id="t", issuer="b")


def test_score_buckets():
    gold = [
        _rec("a", Fields(is_txn=True, direction="debit", amount_paise=100, ref="626523840940",
                         own_acct_tail="1234", vpa="x@ybl")),
        _rec("b", Fields(is_txn=False)),
    ]
    preds = {
        "a": {"is_txn": True, "direction": "debit", "amount_paise": 999, "own_acct_tail": "1234",
              "payee": "X@YBL"},
        "b": {"is_txn": True, "direction": "credit", "amount_paise": 5},
    }
    s = score(gold, preds)
    assert s["is_txn"]["false_capture_rate"] == 1.0
    assert s["fields"]["amount_paise"]["wrong"] == 1.0
    assert s["fields"]["ref"]["missing"] == 1.0
    assert s["fields"]["counterparty"]["correct"] == 1.0
    assert s["core_exact"] == 0.0
