#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUBPROJECT_DIR="$ROOT_DIR/subprojects/ran_replacement"

cd "$ROOT_DIR"

echo "[1/4] Parsing replacement JSON fixtures"
for file in \
  "$SUBPROJECT_DIR"/examples/ranctl/*.json \
  "$SUBPROJECT_DIR"/examples/status/*.json \
  "$SUBPROJECT_DIR"/contracts/*.json \
  "$SUBPROJECT_DIR"/contracts/examples/*.json
do
  jq -e . "$file" >/dev/null
done

echo "[2/4] Validating ranctl replacement request fixtures"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/ranctl-ran-replacement-request-v1.schema.json" \
  -r "$SUBPROJECT_DIR/contracts/open5gs-core-link-profile-v1.schema.json" \
  -d "$SUBPROJECT_DIR/examples/ranctl/*.json"

echo "[3/4] Validating ranctl replacement status fixtures"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/ranctl-ran-replacement-status-v1.schema.json" \
  -d "$SUBPROJECT_DIR/examples/status/*.json"

echo "[4/5] Validating artifact fixtures"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/compare-report-v1.schema.json" \
  -d "$SUBPROJECT_DIR/examples/artifacts/compare-report-*.json"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/rollback-evidence-v1.schema.json" \
  -d "$SUBPROJECT_DIR/examples/artifacts/rollback-evidence-*.json"

echo "[5/5] Validating target-profile example"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/n79-single-ru-target-profile-v1.schema.json" \
  -d "$SUBPROJECT_DIR/contracts/examples/n79-single-ru-target-profile-v1.example.json"

echo "replacement-contract-validation-ok"
