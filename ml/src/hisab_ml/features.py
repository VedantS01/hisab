"""Record -> model inputs: tokenization, BIO tags, sequence class.

Everything here has to be reproduced exactly on device (Swift and Dart), so it
stays deliberately plain: a length-preserving character map, BERT's basic
pre-tokenizer plus a split at letter/digit boundaries, then WordPiece.
"""

from __future__ import annotations

from dataclasses import dataclass

from tokenizers import pre_tokenizers
from transformers import AutoTokenizer, PreTrainedTokenizerFast

from .schema import LABELS, Record

TAGS = ("O",) + tuple(f"{p}-{label}" for label in LABELS for p in ("B", "I"))
TAG_ID = {t: i for i, t in enumerate(TAGS)}
SEQ_CLASSES = ("none", "debit", "credit")
IGNORE = -100

# Characters missing from the uncased BERT vocabulary would turn their whole
# word into [UNK] ("₹450" -> one [UNK]) and hide the amount inside it. Mapping
# them to in-vocabulary symbols of the SAME LENGTH keeps every offset valid.
CHAR_MAP = str.maketrans({"₹": "$", "•": "*"})


def prepare(text: str) -> str:
    return text.translate(CHAR_MAP)


def load_tokenizer(name_or_dir: str) -> PreTrainedTokenizerFast:
    tok = AutoTokenizer.from_pretrained(name_or_dir, use_fast=True)
    # "XX1234" -> "xx" "1234", "INR450" -> "inr" "450": span edges in alerts
    # fall on letter/digit transitions, and WordPiece alone does not cut there.
    tok.backend_tokenizer.pre_tokenizer = pre_tokenizers.Sequence([
        pre_tokenizers.BertPreTokenizer(),
        pre_tokenizers.Digits(individual_digits=False),
    ])
    return tok


@dataclass
class Encoded:
    input_ids: list[int]
    tag_ids: list[int]
    seq_id: int
    misaligned: int   # gold spans whose edges are not token edges (label loss)
    truncated: int    # gold spans cut off by max_len


def seq_class(record: Record) -> int:
    return SEQ_CLASSES.index(record.fields.direction if record.fields.is_txn else "none")


def encode(record: Record, tok: PreTrainedTokenizerFast, max_len: int) -> Encoded:
    enc = tok(prepare(record.text), return_offsets_mapping=True, truncation=True, max_length=max_len)
    offsets = enc["offset_mapping"]
    real = [(s, e) for s, e in offsets if e > s]
    starts, ends = {s for s, _ in real}, {e for _, e in real}
    last_char = max((e for _, e in real), default=0)

    tags = [IGNORE if e <= s else TAG_ID["O"] for s, e in offsets]
    misaligned = truncated = 0
    for span in record.spans:
        if span.start >= last_char:
            truncated += 1
            continue
        if span.start not in starts or span.end not in ends:
            misaligned += 1
        first = True
        for i, (s, e) in enumerate(offsets):
            if e > s and span.start <= s < span.end:
                tags[i] = TAG_ID[f"{'B' if first else 'I'}-{span.label}"]
                first = False
    return Encoded(enc["input_ids"], tags, seq_class(record), misaligned, truncated)
