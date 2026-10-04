"""Score the shipped regex AlertParser (Dart port) on a gold split.

    uv run python bench/baseline_regex.py data/synthetic/test.jsonl
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from hisab_ml.evaluate import format_report, load_gold, score

CORE = Path(__file__).resolve().parents[2] / "hisab_flutter/packages/hisab_core"


def main() -> None:
    gold_path = Path(sys.argv[1])
    gold = load_gold(gold_path)
    stdin = "".join(json.dumps({"id": r.id, "text": r.text}, ensure_ascii=False) + "\n" for r in gold)
    out = subprocess.run(["dart", "run", "tool/alert_baseline.dart"], cwd=CORE, input=stdin,
                         capture_output=True, text=True, check=True).stdout
    preds = {d["id"]: d["fields"] for d in map(json.loads, out.splitlines())}
    pred_path = Path("data/preds") / f"regex-{gold_path.stem}.jsonl"
    pred_path.parent.mkdir(parents=True, exist_ok=True)
    pred_path.write_text(out)
    print(f"regex AlertParser on {gold_path}")
    print(format_report(score(gold, preds)))


if __name__ == "__main__":
    main()
