#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PHASE="${1:-rollback}"

case "${PHASE}" in
  rollback|verify|capture-artifacts)
    shift || true
    exec "${REPO_ROOT}/bin/ranctl" "${PHASE}" "$@"
    ;;
  *)
    echo "Usage: scripts/run.sh [rollback|verify|capture-artifacts] [ranctl args]" >&2
    exit 1
    ;;
esac
