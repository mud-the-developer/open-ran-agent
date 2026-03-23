#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: run_remote_ranctl.sh <target-host> <command> [request-file]

Commands:
  precheck
  plan
  apply
  verify
  rollback
  observe
  capture-artifacts

Environment:
  RAN_SSH_USER             SSH username. Default: current user
  RAN_SSH_PORT             SSH port. Default: 22
  RAN_REMOTE_INSTALL_ROOT  Remote install root. Default: /opt/open-ran-agent
  RAN_REMOTE_ETC_ROOT      Remote config root. Default: /etc/open-ran-agent
  RAN_LOCAL_CONFIG_ROOT    Local preview config root. Default: ./artifacts/deploy_preview/etc when present
  RAN_REMOTE_APPLY         If set to 1, execute the remote command. Otherwise print the plan.
  RAN_REMOTE_FETCH         If set to 1, fetch remote evidence after a successful command. Default: 1
  RAN_REMOTE_RESULT_ROOT   Local result root. Default: ./artifacts/remote_runs
EOF
}

quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
}

single_line() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g'
}

json_field() {
  local file="$1"
  local field="$2"

  tr -d '\n' < "${file}" | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 64
fi

for cmd in bash ssh scp sed tr tee date mkdir; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "required command missing: ${cmd}" >&2
    exit 69
  fi
done

TARGET_HOST="$1"
COMMAND="$2"
REQUEST_FILE="${3:-}"

case "${COMMAND}" in
  precheck|plan|apply|verify|rollback|observe|capture-artifacts) ;;
  *)
    echo "unsupported command: ${COMMAND}" >&2
    exit 64
    ;;
esac

if [[ -n "${RAN_LOCAL_CONFIG_ROOT:-}" ]]; then
  LOCAL_CONFIG_ROOT="${RAN_LOCAL_CONFIG_ROOT}"
elif [[ -d "$(pwd)/artifacts/deploy_preview/etc" ]]; then
  LOCAL_CONFIG_ROOT="$(pwd)/artifacts/deploy_preview/etc"
else
  LOCAL_CONFIG_ROOT=""
fi

if [[ -z "${REQUEST_FILE}" ]]; then
  if [[ -n "${LOCAL_CONFIG_ROOT}" && -f "${LOCAL_CONFIG_ROOT}/requests/precheck-target-host.json" ]]; then
    REQUEST_FILE="${LOCAL_CONFIG_ROOT}/requests/precheck-target-host.json"
  else
    REQUEST_FILE="$(pwd)/examples/ranctl/precheck-target-host.json.example"
  fi
fi

REQUEST_FILE="$(cd "$(dirname "${REQUEST_FILE}")" && pwd)/$(basename "${REQUEST_FILE}")"

if [[ ! -f "${REQUEST_FILE}" ]]; then
  echo "request file not found: ${REQUEST_FILE}" >&2
  exit 66
fi

SSH_USER="${RAN_SSH_USER:-${USER:-ranops}}"
SSH_PORT="${RAN_SSH_PORT:-22}"
REMOTE_INSTALL_ROOT="${RAN_REMOTE_INSTALL_ROOT:-/opt/open-ran-agent}"
REMOTE_ETC_ROOT="${RAN_REMOTE_ETC_ROOT:-/etc/open-ran-agent}"
REMOTE_APPLY="${RAN_REMOTE_APPLY:-0}"
REMOTE_FETCH="${RAN_REMOTE_FETCH:-1}"
RESULT_ROOT="${RAN_REMOTE_RESULT_ROOT:-$(pwd)/artifacts/remote_runs}"

SSH_TARGET="${TARGET_HOST}"
if [[ -n "${SSH_USER}" ]]; then
  SSH_TARGET="${SSH_USER}@${TARGET_HOST}"
fi

REMOTE_CURRENT="${REMOTE_INSTALL_ROOT}/current"
REMOTE_TOPOLOGY_FILE="${REMOTE_ETC_ROOT}/topology.single_du.target_host.rfsim.json"
REMOTE_REQUEST_FILE="${REMOTE_ETC_ROOT}/requests/$(basename "${REQUEST_FILE}")"
CHANGE_ID="$(json_field "${REQUEST_FILE}" "change_id")"
INCIDENT_ID="$(json_field "${REQUEST_FILE}" "incident_id")"
RUN_STAMP="$(date +%Y%m%dT%H%M%S)"
LOCAL_RUN_DIR="${RESULT_ROOT}/${TARGET_HOST}/${RUN_STAMP}-${COMMAND}"
LOCAL_RESULT_FILE="${LOCAL_RUN_DIR}/result.jsonl"
LOCAL_PLAN_FILE="${LOCAL_RUN_DIR}/plan.txt"
LOCAL_COMMAND_LOG="${LOCAL_RUN_DIR}/command.log"
LOCAL_DEBUG_SUMMARY_FILE="${LOCAL_RUN_DIR}/debug-summary.txt"
LOCAL_DEBUG_PACK_FILE="${LOCAL_RUN_DIR}/debug-pack.txt"

mkdir -p "${LOCAL_RUN_DIR}"

CURRENT_STEP="plan"
CURRENT_COMMAND=""
RUN_STATUS="$(if [[ "${REMOTE_APPLY}" == "1" ]]; then echo applying; else echo planned; fi)"
FAILED_STEP=""
FAILED_COMMAND=""
EXIT_CODE=""

write_debug_summary() {
  printf '%s\n' \
    "kind=remote_ranctl" \
    "run_stamp=${RUN_STAMP}" \
    "target_host=${TARGET_HOST}" \
    "ssh_target=${SSH_TARGET}" \
    "command=${COMMAND}" \
    "request_file=${REQUEST_FILE}" \
    "change_id=${CHANGE_ID}" \
    "incident_id=${INCIDENT_ID}" \
    "result_file=${LOCAL_RESULT_FILE}" \
    "plan_file=${LOCAL_PLAN_FILE}" \
    "command_log=${LOCAL_COMMAND_LOG}" \
    "fetch_dir=${FETCH_DIR:-}" \
    "debug_pack_file=${LOCAL_DEBUG_PACK_FILE}" \
    "failed_step=$(single_line "${FAILED_STEP}")" \
    "failed_command=$(single_line "${FAILED_COMMAND}")" \
    "exit_code=${EXIT_CODE}" \
    "status=${RUN_STATUS}" \
    > "${LOCAL_DEBUG_SUMMARY_FILE}"
}

write_debug_pack() {
  cat > "${LOCAL_DEBUG_PACK_FILE}" <<EOF
Debug Pack
  kind        : remote_ranctl
  status      : ${RUN_STATUS}
  target host : ${TARGET_HOST}
  ssh target  : ${SSH_TARGET}
  command     : ${COMMAND}
  change id   : ${CHANGE_ID:-n/a}
  incident id : ${INCIDENT_ID:-n/a}
  failed step : ${FAILED_STEP:-n/a}
  exit code   : ${EXIT_CODE:-n/a}

Inspect next:
  - summary    : ${LOCAL_DEBUG_SUMMARY_FILE}
  - plan       : ${LOCAL_PLAN_FILE}
  - result     : ${LOCAL_RESULT_FILE}
  - command log: ${LOCAL_COMMAND_LOG}
  - fetch dir  : ${FETCH_DIR:-disabled}
EOF
}

mark_failure() {
  local exit_code="${1:-1}"
  RUN_STATUS="failed"
  FAILED_STEP="${CURRENT_STEP:-unknown}"
  FAILED_COMMAND="${CURRENT_COMMAND:-${BASH_COMMAND:-unknown}}"
  EXIT_CODE="${exit_code}"
}

on_error() {
  local exit_code="$?"

  if [[ "${RUN_STATUS}" != "failed" ]]; then
    mark_failure "${exit_code}"
  fi
}

finalize_debug_artifacts() {
  write_debug_summary
  write_debug_pack
}

trap on_error ERR
trap finalize_debug_artifacts EXIT

COMMANDS=(
  "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") mkdir -p $(quote "${REMOTE_ETC_ROOT}/requests")"
)

if [[ -n "${LOCAL_CONFIG_ROOT}" && -f "${LOCAL_CONFIG_ROOT}/topology.single_du.target_host.rfsim.json" ]]; then
  COMMANDS+=(
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_CONFIG_ROOT}/topology.single_du.target_host.rfsim.json") $(quote "${SSH_TARGET}:${REMOTE_TOPOLOGY_FILE}")"
  )
fi

COMMANDS+=(
  "scp -P $(quote "${SSH_PORT}") $(quote "${REQUEST_FILE}") $(quote "${SSH_TARGET}:${REMOTE_REQUEST_FILE}")"
  "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") env RAN_REPO_ROOT=$(quote "${REMOTE_CURRENT}") RAN_TOPOLOGY_FILE=$(quote "${REMOTE_TOPOLOGY_FILE}") $(quote "${REMOTE_CURRENT}/bin/ranctl") ${COMMAND} --file $(quote "${REMOTE_REQUEST_FILE}")"
)

{
  echo "Remote ranctl plan"
  echo "  target host : ${SSH_TARGET}"
  echo "  command     : ${COMMAND}"
  echo "  request file: ${REQUEST_FILE}"
  echo "  change_id   : ${CHANGE_ID:-n/a}"
  echo "  incident_id : ${INCIDENT_ID:-n/a}"
  echo "  result dir  : ${LOCAL_RUN_DIR}"
  echo "  auto fetch  : ${REMOTE_FETCH}"
  echo
  echo "Commands:"
  for command in "${COMMANDS[@]}"; do
    echo "  ${command}"
  done
} | tee "${LOCAL_PLAN_FILE}" >/dev/null

if [[ "${REMOTE_APPLY}" != "1" ]]; then
  cat "${LOCAL_PLAN_FILE}"
  echo
  echo "Set RAN_REMOTE_APPLY=1 to execute the remote command."
  exit 0
fi

: > "${LOCAL_COMMAND_LOG}"

for index in "${!COMMANDS[@]}"; do
  command="${COMMANDS[$index]}"
  CURRENT_COMMAND="${command}"

  if [[ "${index}" == "$((${#COMMANDS[@]} - 1))" ]]; then
    CURRENT_STEP="remote_command"
  elif [[ "${index}" -eq 0 ]]; then
    CURRENT_STEP="request_stage"
  else
    CURRENT_STEP="request_sync"
  fi

  echo "+ ${command}" | tee -a "${LOCAL_COMMAND_LOG}"

  if [[ "${index}" == "$((${#COMMANDS[@]} - 1))" ]]; then
    eval "${command}" 2>&1 | tee "${LOCAL_RESULT_FILE}" | tee -a "${LOCAL_COMMAND_LOG}"
  else
    eval "${command}" 2>&1 | tee -a "${LOCAL_COMMAND_LOG}"
  fi
done

CURRENT_COMMAND=""

FETCH_DIR=""

if [[ "${REMOTE_FETCH}" == "1" ]]; then
  FETCH_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fetch_remote_artifacts.sh"

  if [[ -x "${FETCH_SCRIPT}" ]]; then
    FETCH_DIR="${LOCAL_RUN_DIR}/fetch"
    CURRENT_STEP="fetch_evidence"
    CURRENT_COMMAND="bash ${FETCH_SCRIPT} ${TARGET_HOST} ${REQUEST_FILE}"
    echo "+ local evidence fetch via ${FETCH_SCRIPT}"

    env \
      RAN_SSH_USER="${SSH_USER}" \
      RAN_SSH_PORT="${SSH_PORT}" \
      RAN_REMOTE_INSTALL_ROOT="${REMOTE_INSTALL_ROOT}" \
      RAN_REMOTE_ETC_ROOT="${REMOTE_ETC_ROOT}" \
      RAN_REMOTE_APPLY=1 \
      RAN_REMOTE_OUTPUT_DIR="${FETCH_DIR}" \
      bash "${FETCH_SCRIPT}" "${TARGET_HOST}" "${REQUEST_FILE}"
    CURRENT_COMMAND=""
  fi
fi

RUN_STATUS="$(json_field "${LOCAL_RESULT_FILE}" "status")"

if [[ -z "${RUN_STATUS}" ]]; then
  RUN_STATUS="executed"
fi

cat <<EOF
Remote command completed
  result dir : ${LOCAL_RUN_DIR}
  plan file  : ${LOCAL_PLAN_FILE}
  output     : ${LOCAL_RESULT_FILE}
  command log: ${LOCAL_COMMAND_LOG}
  fetched    : ${FETCH_DIR:-disabled}
  debug pack : ${LOCAL_DEBUG_PACK_FILE}
EOF
