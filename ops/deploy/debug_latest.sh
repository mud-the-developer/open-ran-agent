#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: debug_latest.sh [options]

Options:
  --artifact-root <path>   Artifact root to scan. Default: ./artifacts
  --kind <all|install|remote|fetch>
                           Filter by debug run family. Default: all
  --failures-only          Only consider failed/blocked/error runs
  -h, --help               Show this help

Examples:
  bin/ran-debug-latest
  bin/ran-debug-latest --failures-only
  bin/ran-debug-latest --kind remote --failures-only
EOF
}

kv_field() {
  local file="$1"
  local field="$2"

  sed -n "s/^${field}=//p" "${file}" | head -n 1
}

status_is_failure() {
  local status="${1:-}"
  local lowered

  lowered="$(printf '%s' "${status}" | tr '[:upper:]' '[:lower:]')"

  [[ -n "${lowered}" ]] && {
    [[ "${lowered}" == *fail* ]] ||
      [[ "${lowered}" == *error* ]] ||
      [[ "${lowered}" == *blocked* ]] ||
      [[ "${lowered}" == *denied* ]]
  }
}

kind_matches() {
  local filter="$1"
  local kind="$2"

  case "${filter}" in
    all) return 0 ;;
    install) [[ "${kind}" == "quick_install" || "${kind}" == "ship_bundle" ]] ;;
    remote) [[ "${kind}" == "remote_ranctl" ]] ;;
    fetch) [[ "${kind}" == "fetch_remote_artifacts" ]] ;;
    *) return 1 ;;
  esac
}

ARTIFACT_ROOT="$(pwd)/artifacts"
KIND_FILTER="all"
FAILURES_ONLY="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-root)
      ARTIFACT_ROOT="$2"
      shift 2
      ;;
    --kind)
      KIND_FILTER="$2"
      shift 2
      ;;
    --failures-only)
      FAILURES_ONLY="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

ARTIFACT_ROOT="$(cd "$(dirname "${ARTIFACT_ROOT}")" && pwd)/$(basename "${ARTIFACT_ROOT}")"

shopt -s nullglob
SUMMARY_FILES=(
  "${ARTIFACT_ROOT}"/deploy_preview/quick_install/*/debug-summary.txt
  "${ARTIFACT_ROOT}"/install_runs/*/*/debug-summary.txt
  "${ARTIFACT_ROOT}"/remote_runs/*/*/debug-summary.txt
  "${ARTIFACT_ROOT}"/remote_runs/*/*/fetch/debug-summary.txt
)
shopt -u nullglob

LATEST_FILE=""
LATEST_MTIME=0

for summary_file in "${SUMMARY_FILES[@]}"; do
  [[ -f "${summary_file}" ]] || continue

  kind="$(kv_field "${summary_file}" "kind")"
  status="$(kv_field "${summary_file}" "status")"

  if ! kind_matches "${KIND_FILTER}" "${kind}"; then
    continue
  fi

  if [[ "${FAILURES_ONLY}" == "1" ]] && ! status_is_failure "${status}"; then
    continue
  fi

  mtime="$(stat -c %Y "${summary_file}" 2>/dev/null || printf '0')"

  if (( mtime > LATEST_MTIME )); then
    LATEST_MTIME="${mtime}"
    LATEST_FILE="${summary_file}"
  fi
done

if [[ -z "${LATEST_FILE}" ]]; then
  if [[ "${FAILURES_ONLY}" == "1" ]]; then
    echo "No failed debug runs found under ${ARTIFACT_ROOT}."
  else
    echo "No debug runs found under ${ARTIFACT_ROOT}."
  fi

  exit 0
fi

RUN_DIR="$(dirname "${LATEST_FILE}")"
KIND="$(kv_field "${LATEST_FILE}" "kind")"
STATUS="$(kv_field "${LATEST_FILE}" "status")"
TARGET_HOST="$(kv_field "${LATEST_FILE}" "target_host")"
COMMAND="$(kv_field "${LATEST_FILE}" "command")"
DEPLOY_PROFILE="$(kv_field "${LATEST_FILE}" "deploy_profile")"
FAILED_STEP="$(kv_field "${LATEST_FILE}" "failed_step")"
FAILED_COMMAND="$(kv_field "${LATEST_FILE}" "failed_command")"
EXIT_CODE="$(kv_field "${LATEST_FILE}" "exit_code")"
CHANGE_ID="$(kv_field "${LATEST_FILE}" "change_id")"
INCIDENT_ID="$(kv_field "${LATEST_FILE}" "incident_id")"
REQUEST_FILE="$(kv_field "${LATEST_FILE}" "request_file")"
PLAN_FILE="$(kv_field "${LATEST_FILE}" "plan_file")"
TRANSCRIPT_FILE="$(kv_field "${LATEST_FILE}" "transcript_file")"
RESULT_FILE="$(kv_field "${LATEST_FILE}" "result_file")"
COMMAND_LOG="$(kv_field "${LATEST_FILE}" "command_log")"
DEBUG_PACK_FILE="$(kv_field "${LATEST_FILE}" "debug_pack_file")"
READINESS_FILE="$(kv_field "${LATEST_FILE}" "readiness_file")"

cat <<EOF
Latest Debug Run
  kind         : ${KIND:-unknown}
  status       : ${STATUS:-unknown}
  target host  : ${TARGET_HOST:-n/a}
  command      : ${COMMAND:-n/a}
  deploy profile: ${DEPLOY_PROFILE:-n/a}
  change id    : ${CHANGE_ID:-n/a}
  incident id  : ${INCIDENT_ID:-n/a}
  failed step  : ${FAILED_STEP:-n/a}
  exit code    : ${EXIT_CODE:-n/a}
  summary      : ${LATEST_FILE}
  run dir      : ${RUN_DIR}

Inspect next:
  - debug pack : ${DEBUG_PACK_FILE:-n/a}
  - plan       : ${PLAN_FILE:-n/a}
  - result     : ${RESULT_FILE:-n/a}
  - transcript : ${TRANSCRIPT_FILE:-${COMMAND_LOG:-n/a}}
  - request    : ${REQUEST_FILE:-n/a}
  - readiness  : ${READINESS_FILE:-n/a}
EOF

if [[ -n "${FAILED_COMMAND}" ]]; then
  echo
  echo "Failed command"
  echo "  ${FAILED_COMMAND}"
fi
