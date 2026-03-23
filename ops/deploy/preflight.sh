#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${RAN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
REQUEST_FILE="${RAN_PREFLIGHT_REQUEST:-${ROOT_DIR}/examples/ranctl/precheck-target-host.json.example}"
MIX_ENV="${MIX_ENV:-prod}"

for cmd in bash elixir mix tar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "required command missing: ${cmd}" >&2
    exit 69
  fi
done

if [[ ! -f "${REQUEST_FILE}" ]]; then
  echo "preflight request not found: ${REQUEST_FILE}" >&2
  exit 66
fi

if [[ -n "${RAN_TOPOLOGY_FILE:-}" && ! -f "${RAN_TOPOLOGY_FILE}" ]]; then
  echo "topology file not found: ${RAN_TOPOLOGY_FILE}" >&2
  exit 66
fi

cd "${ROOT_DIR}"
exec env MIX_ENV="${MIX_ENV}" RAN_TOPOLOGY_FILE="${RAN_TOPOLOGY_FILE:-}" \
  "${ROOT_DIR}/bin/ranctl" precheck --file "${REQUEST_FILE}"
