import numpy as np
import pytest

from hisab_ml.features import SEQ_CLASSES, TAG_ID, TAGS, prepare
from hisab_ml.predict import decode, spans_from_tags


def _logits(tags: list[str]) -> np.ndarray:
    x = np.full((len(tags), len(TAGS)), -10.0)
    for i, t in enumerate(tags):
        x[i, TAG_ID[t]] = 10.0
    return x


def _seq(cls: str) -> np.ndarray:
    x = np.full(len(SEQ_CLASSES), -10.0)
    x[SEQ_CLASSES.index(cls)] = 10.0
    return x


TEXT = "Rs.1,234.50 debited from a/c XX1234 Ref 626523840940"
# Offsets as the tokenizer would give them (special tokens are (0, 0)).
OFFSETS = [(0, 0), (0, 2), (2, 3), (3, 4), (4, 5), (5, 8), (8, 9), (9, 11), (12, 19), (20, 24),
           (25, 28), (29, 31), (31, 35), (36, 39), (40, 52), (0, 0)]
TAGS_GOLD = ["O", "O", "O", "B-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "O", "O",
             "O", "B-OWN_ACCT", "I-OWN_ACCT", "O", "B-REF", "O"]


def test_spans_from_tags_rebuilds_char_spans():
    spans = spans_from_tags(OFFSETS, _logits(TAGS_GOLD))
    assert [(label, TEXT[s:e]) for label, s, e, _ in spans] == [
        ("AMOUNT", "1,234.50"), ("OWN_ACCT", "XX1234"), ("REF", "626523840940")]


def test_decode_fields():
    f = decode(TEXT, OFFSETS, _logits(TAGS_GOLD), _seq("debit"))
    assert f["is_txn"] and f["direction"] == "debit"
    assert (f["amount_paise"], f["own_acct_tail"], f["ref"]) == (123450, "1234", "626523840940")


def test_non_transaction_emits_no_fields():
    f = decode(TEXT, OFFSETS, _logits(TAGS_GOLD), _seq("none"))
    assert f["is_txn"] is False and "amount_paise" not in f


def test_span_that_fails_normalization_is_dropped():
    # A model tagging "Rs." as the amount yields nothing rather than a guess.
    tags = ["O", "B-AMOUNT", "I-AMOUNT"] + ["O"] * (len(OFFSETS) - 3)
    f = decode(TEXT, OFFSETS, _logits(tags), _seq("debit"))
    assert "amount_paise" not in f


def test_orphan_inside_tag_opens_a_span():
    tags = ["O", "O", "O", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT", "I-AMOUNT"] + ["O"] * 8
    assert spans_from_tags(OFFSETS, _logits(tags))[0][0] == "AMOUNT"


def test_clean_edges_rejects_slices_of_longer_runs():
    from hisab_ml.predict import clean_edges

    t = "UMRN: HDFC7020902210002459 Ref 626523840940"
    whole = t.index("626523840940")
    assert clean_edges(t, whole, whole + 12)
    inner = t.index("902210002459")
    assert not clean_edges(t, inner, inner + 12)          # starts mid digit-run
    assert clean_edges(t, t.index("7020902210002459"), t.index(" Ref"))  # letter->digit edge is fine
    assert not clean_edges(t, t.index("DFC"), t.index("7020"))           # starts mid letter-run

    amt = "INR 3,13,938.00 credited"
    assert clean_edges(amt, 4, 15)
    assert not clean_edges(amt, 13, 15)   # "00" after the decimal point
    assert not clean_edges(amt, 4, 8)     # "3,13" stops before ",938"
    pan = "PAN XXXXXX984D, A/c XX8816"
    assert not clean_edges(pan, 4, 13)    # "XXXXXX984" ends inside "XXXXXX984D"
    assert clean_edges(pan, pan.index("XX8816"), len(pan))


def test_names_drop_honorifics():
    from hisab_ml import normalize

    assert normalize.name("Mr MO ALAM") == normalize.name("MO ALAM") == "mo alam"
    assert normalize.name("Dr. Priya Nair") == "priya nair"
    assert normalize.name("Mrinal Sen") == "mrinal sen"


def test_prepare_preserves_length():
    s = "₹450 paid to X\nHDFC ••1234"
    assert len(prepare(s)) == len(s) and "₹" not in prepare(s)


@pytest.mark.model
def test_every_gold_span_lands_on_token_edges():
    import random

    from hisab_ml.features import encode, load_tokenizer
    from hisab_ml.generate import make_record
    from hisab_ml.templates import TEMPLATES

    tok = load_tokenizer("google/electra-small-discriminator")
    rng = random.Random(1)
    bad = [(t.id, e.misaligned) for t in TEMPLATES for i in range(50)
           if (e := encode(make_record(t, i, rng), tok, 192)).misaligned or e.truncated]
    assert not bad, bad[:10]
