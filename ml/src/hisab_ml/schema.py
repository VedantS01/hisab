"""The record format every stage reads and writes.

A record is one alert text plus character-offset spans. Spans are the
supervision signal (tokenizer-agnostic: the training step aligns them to
whatever tokens the encoder uses). `fields` is the normalized answer the app
needs, derived from the spans — the evaluator scores predictions against it.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

# Extractive labels. Every value the model returns is a substring of the input,
# which is what makes the extractor incapable of inventing a value.
LABELS = (
    "AMOUNT",     # the transaction amount, digits only ("1,23,456.78")
    "REF",        # rail reference: UPI RRN, IMPS ref, NEFT/RTGS UTR
    "PAYEE",      # counterparty name or merchant as written
    "VPA",        # counterparty UPI id
    "OWN_ACCT",   # the user's account or card, masked as written ("XX1234")
    "CPTY_ACCT",  # the counterparty's account, masked as written
    "DATE",       # the transaction's date as written
    "BALANCE",    # available balance after the transaction, digits only
)

CHANNELS = ("sms", "notification", "email")


@dataclass(frozen=True)
class Span:
    start: int
    end: int
    label: str


@dataclass
class Fields:
    """What Hisab needs from one alert. None means absent from the text."""

    is_txn: bool
    direction: str | None = None        # "debit" | "credit"
    amount_paise: int | None = None
    ref: str | None = None
    payee: str | None = None
    vpa: str | None = None
    own_acct_tail: str | None = None    # trailing digits only
    cpty_acct_tail: str | None = None
    date_iso: str | None = None
    balance_paise: int | None = None


@dataclass
class Record:
    id: str
    text: str
    spans: list[Span]
    fields: Fields
    channel: str
    template_id: str
    issuer: str
    meta: dict = field(default_factory=dict)

    def to_json(self) -> dict:
        return asdict(self)

    @classmethod
    def from_json(cls, d: dict) -> Record:
        return cls(
            id=d["id"],
            text=d["text"],
            spans=[Span(**s) for s in d["spans"]],
            fields=Fields(**d["fields"]),
            channel=d["channel"],
            template_id=d["template_id"],
            issuer=d["issuer"],
            meta=d.get("meta", {}),
        )
