#!/bin/bash
# Syncs single-source data assets from HisabCore into the Flutter tree.
#   tool/sync_assets.sh          copy
#   tool/sync_assets.sh --check  fail if the copies have drifted (CI)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC_FORMATS="HisabCore/Sources/HisabCore/Resources/formats"
SRC_RULESETS="HisabCore/Sources/HisabCore/Resources/rulesets"
SRC_INSIGHTS="HisabCore/Sources/HisabCore/Resources/insights"
SRC_FIXTURES="HisabCore/Tests/HisabCoreTests/Fixtures"
DST_FORMATS="hisab_flutter/assets/formats"
DST_RULESETS="hisab_flutter/assets/rulesets"
DST_INSIGHTS="hisab_flutter/assets/insights"
DST_FIXTURES="hisab_flutter/packages/hisab_core/test/fixtures"
# The extractor's tokenizer data is shared; each platform keeps its own model
# (iOS: Extractor.mlmodelc in HisabCore; Android: extractor.int8.onnx in assets).
SRC_EXTRACTOR="HisabCore/Sources/HisabCore/Resources/extractor"
DST_EXTRACTOR="hisab_flutter/assets/extractor"
EXTRACTOR_FILES="vocab.txt chartable.json extractor.json"

if [[ "${1:-}" == "--check" ]]; then
  fail=0
  for pair in "$SRC_FORMATS:$DST_FORMATS" "$SRC_RULESETS:$DST_RULESETS" "$SRC_INSIGHTS:$DST_INSIGHTS" "$SRC_FIXTURES:$DST_FIXTURES"; do
    src="${pair%%:*}"; dst="${pair##*:}"
    if ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
      echo "DRIFT: $dst differs from $src (run tool/sync_assets.sh)"
      fail=1
    fi
  done
  for f in $EXTRACTOR_FILES; do
    if ! cmp -s "$SRC_EXTRACTOR/$f" "$DST_EXTRACTOR/$f"; then
      echo "DRIFT: $DST_EXTRACTOR/$f differs from $SRC_EXTRACTOR/$f (run tool/sync_assets.sh)"
      fail=1
    fi
  done
  exit $fail
fi

rm -rf "$DST_FORMATS" "$DST_RULESETS" "$DST_INSIGHTS" "$DST_FIXTURES"
mkdir -p "$DST_FORMATS" "$DST_RULESETS" "$DST_INSIGHTS" "$DST_FIXTURES"
cp "$SRC_FORMATS"/* "$DST_FORMATS"/
cp "$SRC_RULESETS"/* "$DST_RULESETS"/
cp "$SRC_INSIGHTS"/* "$DST_INSIGHTS"/
cp "$SRC_FIXTURES"/* "$DST_FIXTURES"/
mkdir -p "$DST_EXTRACTOR"
for f in $EXTRACTOR_FILES; do cp "$SRC_EXTRACTOR/$f" "$DST_EXTRACTOR/$f"; done
echo "synced formats, rulesets, insights, fixtures, extractor"
