#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PHASE="${1:-plan}"

case "${PHASE}" in
  observe|precheck|plan|apply|verify|rollback|capture-artifacts)
    shift || true
    exec "${REPO_ROOT}/bin/ranctl" "${PHASE}" "$@"
    ;;
  *)
    echo "Usage: scripts/run.sh [observe|precheck|plan|apply|verify|rollback|capture-artifacts] [ranctl args]" >&2
    exit 1
    ;;
esac
