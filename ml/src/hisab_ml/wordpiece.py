"""Reference tokenizer: the exact algorithm the Swift and Dart ports implement.

It reproduces the Hugging Face pipeline the model was trained with (BERT
normalizer -> BERT pre-tokenizer -> Digits -> WordPiece, uncased) without the
`tokenizers` library, so that every step is a few lines a port can copy. The
Unicode facts it needs (accent stripping, lowercase, punctuation, digit and
whitespace classes) come from `chartable.json`, generated here from Python's
unicodedata — Dart's standard library has none of them, and two ports reading
one table cannot drift apart.

All indices are Unicode scalar (code point) indices into the ORIGINAL text,
after `features.prepare`'s same-length character map.

    uv run python -m hisab_ml.wordpiece table out/chartable.json
    uv run python -m hisab_ml.wordpiece verify      # == HF tokenizer on every alert we have
"""

from __future__ import annotations

import json
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path

CLS, SEP, UNK = "[CLS]", "[SEP]", "[UNK]"
MAX_WORD_CHARS = 100
# BERT's CJK blocks: each ideograph becomes its own word.
CJK = ((0x4E00, 0x9FFF), (0x3400, 0x4DBF), (0x20000, 0x2A6DF), (0x2A700, 0x2B73F), (0x2B740, 0x2B81F),
       (0x2B820, 0x2CEAF), (0xF900, 0xFAFF), (0x2F800, 0x2FA1F))
WHITE_SPACE = {0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, *range(0x2000, 0x200B), 0x2028, 0x2029,
               0x202F, 0x205F, 0x3000}
HANGUL = (0xAC00, 0xD7A3)  # out of scope: left as-is (no Korean in Indian bank alerts)
TABLE_LIMIT = 0x30000      # scalars above this map to themselves


# ---------------------------------------------------------------- the table

def _ranges(cps: list[int]) -> list[list[int]]:
    out: list[list[int]] = []
    for cp in sorted(cps):
        if out and cp == out[-1][1] + 1:
            out[-1][1] = cp
        else:
            out.append([cp, cp])
    return out


def _is_other(cp: int) -> bool:
    return unicodedata.category(chr(cp)) in ("Cc", "Cf", "Cn", "Co", "Cs")


def build_table() -> dict:
    """removed: scalars the normalizer deletes; map: scalar -> replacement
    (NFD, drop nonspacing marks, lowercase) where that is not the scalar
    itself; punct / numeric: non-ASCII classes for the pre-tokenizers."""
    removed, mapping, punct, numeric = [], {}, [], []
    for cp in range(TABLE_LIMIT):
        if HANGUL[0] <= cp <= HANGUL[1] or 0xD800 <= cp <= 0xDFFF:
            continue
        c = chr(cp)
        cat = unicodedata.category(c)
        if cp >= 0x80 and cat.startswith("P"):
            punct.append(cp)
        if cat in ("Nd", "Nl", "No"):
            numeric.append(cp)
        if cp in (0x09, 0x0A, 0x0D) or cp in WHITE_SPACE:
            continue  # whitespace becomes a space; handled by rule
        if cp == 0 or cp == 0xFFFD or _is_other(cp):
            removed.append(cp)
            continue
        out = "".join(ch for ch in unicodedata.normalize("NFD", c) if unicodedata.category(ch) != "Mn").lower()
        if out == "":
            removed.append(cp)
        elif out != c:
            mapping[cp] = out
    return {
        "version": 1,
        "unicode": unicodedata.unidata_version,
        "removed": _ranges(removed),
        "map": {str(k): v for k, v in sorted(mapping.items())},
        "punct": _ranges(punct),
        "numeric": _ranges(numeric),
    }


class Table:
    def __init__(self, d: dict):
        self.removed = [tuple(r) for r in d["removed"]]
        self.map = {int(k): v for k, v in d["map"].items()}
        self.punct = [tuple(r) for r in d["punct"]]
        self.numeric = [tuple(r) for r in d["numeric"]]

    @staticmethod
    def _in(ranges, cp: int) -> bool:
        lo, hi = 0, len(ranges) - 1
        while lo <= hi:
            mid = (lo + hi) // 2
            a, b = ranges[mid]
            if cp < a:
                hi = mid - 1
            elif cp > b:
                lo = mid + 1
            else:
                return True
        return False

    def is_removed(self, cp: int) -> bool:
        return self._in(self.removed, cp)

    def is_punct(self, cp: int) -> bool:
        return (0x21 <= cp <= 0x2F or 0x3A <= cp <= 0x40 or 0x5B <= cp <= 0x60 or 0x7B <= cp <= 0x7E
                or self._in(self.punct, cp))

    def is_numeric(self, cp: int) -> bool:
        return self._in(self.numeric, cp)


# ------------------------------------------------------------ the tokenizer

@dataclass
class Encoding:
    ids: list[int]
    offsets: list[tuple[int, int]]   # (0, 0) for [CLS] and [SEP]


def _normalize(text: str, table: Table) -> list[tuple[str, int]]:
    """(normalized character, index of the original scalar it came from)."""
    out: list[tuple[str, int]] = []
    for i, c in enumerate(text):
        cp = ord(c)
        if cp in WHITE_SPACE:
            out.append((" ", i))
        elif table.is_removed(cp):
            continue
        elif any(a <= cp <= b for a, b in CJK):
            out.extend(((" ", i), (c, i), (" ", i)))
        else:
            out.extend((ch, i) for ch in table.map.get(cp, c))
    return out


def _words(norm: list[tuple[str, int]], table: Table) -> list[list[tuple[str, int]]]:
    """Split on whitespace (dropped), isolate each punctuation character, then
    split digit runs from everything else."""
    words: list[list[tuple[str, int]]] = []
    cur: list[tuple[str, int]] = []

    def flush():
        nonlocal cur
        if cur:
            words.append(cur)
        cur = []

    for ch, i in norm:
        cp = ord(ch)
        if ch == " ":
            flush()
        elif table.is_punct(cp):
            flush()
            words.append([(ch, i)])
        else:
            if cur and table.is_numeric(ord(cur[-1][0])) != table.is_numeric(cp):
                flush()
            cur.append((ch, i))
    flush()
    return words


def _wordpiece(word: list[tuple[str, int]], vocab: dict[str, int]) -> list[tuple[int, int, int]]:
    """(id, start index into word, end index) pieces, or one [UNK] for the word."""
    chars = "".join(ch for ch, _ in word)
    if len(chars) > MAX_WORD_CHARS:
        return [(vocab[UNK], 0, len(chars))]
    pieces, start = [], 0
    while start < len(chars):
        end, hit = len(chars), None
        while start < end:
            sub = chars[start:end] if start == 0 else "##" + chars[start:end]
            if sub in vocab:
                hit = vocab[sub]
                break
            end -= 1
        if hit is None:
            return [(vocab[UNK], 0, len(chars))]
        pieces.append((hit, start, end))
        start = end
    return pieces


def encode(text: str, vocab: dict[str, int], table: Table, max_len: int) -> Encoding:
    ids, offsets = [vocab[CLS]], [(0, 0)]
    for word in _words(_normalize(text, table), table):
        for piece_id, s, e in _wordpiece(word, vocab):
            if len(ids) == max_len - 1:
                break
            ids.append(piece_id)
            offsets.append((word[s][1], word[e - 1][1] + 1))
    ids.append(vocab[SEP])
    offsets.append((0, 0))
    return Encoding(ids, offsets)


def load_vocab(path: Path) -> dict[str, int]:
    """vocab.txt (one token per line, id = line number), or a HF tokenizer.json."""
    if path.suffix == ".json":
        return json.loads(path.read_text(encoding="utf-8"))["model"]["vocab"]
    return {line: i for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")) if line}


def write_vocab_txt(vocab: dict[str, int], path: Path) -> None:
    by_id = sorted(vocab.items(), key=lambda kv: kv[1])
    assert [i for _, i in by_id] == list(range(len(by_id))), "vocab ids must be dense"
    assert all("\n" not in tok for tok, _ in by_id)
    path.write_text("\n".join(tok for tok, _ in by_id) + "\n", encoding="utf-8")


# ------------------------------------------------------------------ checks

def verify(model_dir: Path, texts: list[str], max_len: int) -> int:
    from .features import load_tokenizer, prepare

    tok = load_tokenizer(str(model_dir / "tokenizer"))
    vocab = load_vocab(model_dir / "tokenizer" / "tokenizer.json")
    table = Table(build_table())
    bad = 0
    for t in texts:
        p = prepare(t)
        hf = tok(p, return_offsets_mapping=True, truncation=True, max_length=max_len)
        ours = encode(p, vocab, table, max_len)
        if hf["input_ids"] != ours.ids or [tuple(o) for o in hf["offset_mapping"]] != ours.offsets:
            bad += 1
            if bad <= 5:
                print("MISMATCH", repr(t[:80]))
    print(f"verified {len(texts)} texts, {bad} mismatches")
    return bad


def main() -> None:
    if sys.argv[1] == "table":
        Path(sys.argv[2]).write_text(json.dumps(build_table(), ensure_ascii=False, separators=(",", ":")) + "\n")
        return
    from .evaluate import load_gold

    texts = [json.loads(l)["text"] for l in Path("data/real/messages_raw.jsonl").read_text().splitlines() if l.strip()]
    for f in ("train", "val", "test"):
        texts += [r.text for r in load_gold(Path(f"data/synthetic-v4/{f}.jsonl"))[:4000]]
    texts += EDGE_CASES
    sys.exit(1 if verify(Path("data/models/v4"), texts, 192) else 0)


# Hand-written inputs that exercise every branch; also the committed fixtures.
EDGE_CASES = [
    "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. Ref 123456789012.",
    "₹1,23,456.78 paid to Café Côte d'Azur • HDFC ••1234",
    "INR450 credited\tto A/C*3293\r\nOn 14-08",
    "Naïve résumé ÀÉÎÕÜ ß İstanbul ﬁle Ⅻ ½ ² ௧௨ ٣",
    "உங்கள் கணக்கில் ரூ. 500 வரவு வைக்கப்பட்டது",
    "आपके खाते से ₹200 डेबिट किए गए",
    "中文测试 Rs 99 支付",
    "zero​width­soft﻿bom and \x00nul",
    "a" * 120 + " long-word 1" + "2" * 110,
    "Emoji 🎉 payment ✅ of Rs 50 — done…",
    "Your A/c XX8816 debited by Rs. 30.00 on 12/09/26; Mr MO ALAM credited. RRN 625533739003.",
]


if __name__ == "__main__":
    main()
