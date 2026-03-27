#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUBPROJECT_DIR="$ROOT_DIR/subprojects/ran_replacement"

cd "$ROOT_DIR"

echo "[1/6] Parsing replacement JSON fixtures"
for file in \
  "$SUBPROJECT_DIR"/examples/ranctl/*.json \
  "$SUBPROJECT_DIR"/examples/status/*.json \
  "$SUBPROJECT_DIR"/contracts/*.json \
  "$SUBPROJECT_DIR"/contracts/examples/*.json \
  "$SUBPROJECT_DIR"/packages/*/examples/*.json
do
  jq -e . "$file" >/dev/null
done

echo "[2/6] Validating ranctl replacement request fixtures"
npx --yes ajv-cli validate \
  --spec=draft2020 \
  --strict=false \
  --validate-formats=false \
  -s "$SUBPROJECT_DIR/contracts/ranctl-ran-replacement-request-v1.schema.json" \
  -r "$SUBPROJECT_DIR/contracts/open5gs-core-link-profile-v1.schema.json" \
  -d "$SUBPROJECT_DIR/examples/ranctl/*.json" \
  -d "$SUBPROJECT_DIR/packages/*/examples/*.request.json"

echo "[3/6] Validating ranctl replacement status fixtures"
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

echo "[6/6] Verifying protocol-claim surfaces stay aligned"
node <<'EOF'
const fs = require("fs");
const path = require("path");

const rootDir = process.cwd();
const subprojectDir = path.join(rootDir, "subprojects", "ran_replacement");
const targetClaims = JSON.parse(
  fs.readFileSync(
    path.join(
      subprojectDir,
      "contracts",
      "examples",
      "n79-single-ru-target-profile-v1.example.json"
    ),
    "utf8"
  )
).standards_subset;

const files = [
  ...fs
    .readdirSync(path.join(subprojectDir, "examples", "status"))
    .filter((name) => name.endsWith(".json"))
    .map((name) => path.join(subprojectDir, "examples", "status", name)),
  ...fs
    .readdirSync(path.join(subprojectDir, "examples", "artifacts"))
    .filter((name) => name.endsWith(".json"))
    .map((name) => path.join(subprojectDir, "examples", "artifacts", name)),
  ...["ngap_edge", "f1e1_control_edge", "target_host_edge"]
    .map((dir) => path.join(subprojectDir, "packages", dir, "examples"))
    .flatMap((dir) =>
      fs
        .readdirSync(dir)
        .filter((name) => name.endsWith(".status.json"))
        .map((name) => path.join(dir, name))
    )
];

const targetClaimsJson = JSON.stringify(targetClaims);
const targetNgapJson = JSON.stringify(targetClaims.ngap);

for (const file of files) {
  const payload = JSON.parse(fs.readFileSync(file, "utf8"));
  if (JSON.stringify(payload.protocol_claims) !== targetClaimsJson) {
    throw new Error(`${file} protocol_claims do not match the canonical target-profile standards_subset`);
  }

  if (
    Object.prototype.hasOwnProperty.call(payload, "ngap_subset") &&
    JSON.stringify(payload.ngap_subset) !== targetNgapJson
  ) {
    throw new Error(`${file} ngap_subset does not match protocol_claims.ngap`);
  }
}
EOF

echo "replacement-contract-validation-ok"
