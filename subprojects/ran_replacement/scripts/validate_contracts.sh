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
  "$SUBPROJECT_DIR"/contracts/examples/*.json \
  "$SUBPROJECT_DIR"/packages/*/examples/*.json
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
  -d "$SUBPROJECT_DIR/examples/ranctl/*.json" \
  -d "$SUBPROJECT_DIR/packages/*/examples/*.request.json"

echo "[3/4] Validating ranctl replacement status fixtures"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/ranctl-ran-replacement-status-v1.schema.json" \
  -d "$SUBPROJECT_DIR/examples/status/*.json" \
  -d "$SUBPROJECT_DIR/packages/*/examples/*.status.json"

echo "[4/6] Validating artifact fixtures"
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

echo "[5/6] Validating target-profile and overlay examples"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/n79-single-ru-target-profile-v1.schema.json" \
  -d "$SUBPROJECT_DIR/contracts/examples/n79-single-ru-target-profile-v1.example.json"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/n79-single-ru-target-profile-overlay-v1.schema.json" \
  -d "$SUBPROJECT_DIR/contracts/examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json"

echo "[6/6] Validating topology-scope profile examples"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/topology-scope-profile-v1.schema.json" \
  -d "$SUBPROJECT_DIR/contracts/examples/topology-scope-*.example.json"

echo "replacement-contract-validation-ok"
