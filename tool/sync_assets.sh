#!/bin/bash
# Syncs single-source data assets from HisabCore into the Flutter tree.
#   tool/sync_assets.sh          copy
#   tool/sync_assets.sh --check  fail if the copies have drifted (CI)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC_FORMATS="HisabCore/Sources/HisabCore/Resources/formats"
SRC_RULESETS="HisabCore/Sources/HisabCore/Resources/rulesets"
SRC_FIXTURES="HisabCore/Tests/HisabCoreTests/Fixtures"
DST_FORMATS="hisab_flutter/assets/formats"
DST_RULESETS="hisab_flutter/assets/rulesets"
DST_FIXTURES="hisab_flutter/packages/hisab_core/test/fixtures"

if [[ "${1:-}" == "--check" ]]; then
  fail=0
  for pair in "$SRC_FORMATS:$DST_FORMATS" "$SRC_RULESETS:$DST_RULESETS" "$SRC_FIXTURES:$DST_FIXTURES"; do
    src="${pair%%:*}"; dst="${pair##*:}"
    if ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
      echo "DRIFT: $dst differs from $src (run tool/sync_assets.sh)"
      fail=1
    fi
  done
  exit $fail
fi

rm -rf "$DST_FORMATS" "$DST_RULESETS" "$DST_FIXTURES"
mkdir -p "$DST_FORMATS" "$DST_RULESETS" "$DST_FIXTURES"
cp "$SRC_FORMATS"/* "$DST_FORMATS"/
cp "$SRC_RULESETS"/* "$DST_RULESETS"/
cp "$SRC_FIXTURES"/* "$DST_FIXTURES"/
echo "synced formats, rulesets, fixtures"
