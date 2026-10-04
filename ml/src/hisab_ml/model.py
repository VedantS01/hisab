"""Encoder + two heads: BIO tags per token, and none/debit/credit per alert."""

from __future__ import annotations

import json
from pathlib import Path

import torch
from torch import nn
from transformers import AutoConfig, AutoModel

from .features import SEQ_CLASSES, TAGS, load_tokenizer


class Extractor(nn.Module):
    def __init__(self, encoder: nn.Module):
        super().__init__()
        self.encoder = encoder
        hidden = encoder.config.hidden_size
        self.dropout = nn.Dropout(0.1)
        self.tag_head = nn.Linear(hidden, len(TAGS))
        self.seq_head = nn.Linear(hidden, len(SEQ_CLASSES))

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor):
        h = self.encoder(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
        h = self.dropout(h)
        return self.tag_head(h), self.seq_head(h[:, 0])


def save(model: Extractor, tok, out: Path, meta: dict) -> None:
    out.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out / "model.pt")
    model.encoder.config.save_pretrained(out / "encoder")
    tok.save_pretrained(out / "tokenizer")
    (out / "meta.json").write_text(json.dumps({**meta, "tags": TAGS, "seq_classes": SEQ_CLASSES},
                                              indent=2) + "\n")


def load(model_dir: Path):
    """Model, tokenizer and meta from a saved directory — no network."""
    meta = json.loads((model_dir / "meta.json").read_text())
    assert tuple(meta["tags"]) == TAGS and tuple(meta["seq_classes"]) == SEQ_CLASSES
    encoder = AutoModel.from_config(AutoConfig.from_pretrained(model_dir / "encoder"))
    model = Extractor(encoder)
    model.load_state_dict(torch.load(model_dir / "model.pt", map_location="cpu"))
    model.eval()
    return model, load_tokenizer(str(model_dir / "tokenizer")), meta


def new(base: str) -> Extractor:
    return Extractor(AutoModel.from_pretrained(base))
