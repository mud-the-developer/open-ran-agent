#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ship_bundle.sh <bundle-tarball> <target-host>

Environment:
  RAN_SSH_USER                SSH username. Default: current user
  RAN_SSH_PORT                SSH port. Default: 22
  RAN_LOCAL_CONFIG_ROOT       Local preview config root. Default: ./artifacts/deploy_preview/etc when present
  RAN_REMOTE_BUNDLE_DIR       Remote staging dir. Default: /tmp/open-ran-agent
  RAN_REMOTE_INSTALL_ROOT     Remote install root. Default: /opt/open-ran-agent
  RAN_REMOTE_ETC_ROOT         Remote config root. Default: /etc/open-ran-agent
  RAN_REMOTE_SYSTEMD_DIR      Remote systemd staging dir. Default: <install-root>/systemd
  RAN_INSTALL_LOG_ROOT        Local log root. Default: ./artifacts/install_runs
  RAN_REMOTE_APPLY            If set to 1, execute ssh/scp commands instead of printing them
EOF
}

quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
}

single_line() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 64
fi

for cmd in bash scp ssh tee date mkdir; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "required command missing: ${cmd}" >&2
    exit 69
  fi
done

BUNDLE_TARBALL="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
TARGET_HOST="$2"
SSH_USER="${RAN_SSH_USER:-${USER:-ranops}}"
SSH_PORT="${RAN_SSH_PORT:-22}"
REMOTE_BUNDLE_DIR="${RAN_REMOTE_BUNDLE_DIR:-/tmp/open-ran-agent}"
REMOTE_INSTALL_ROOT="${RAN_REMOTE_INSTALL_ROOT:-/opt/open-ran-agent}"
REMOTE_ETC_ROOT="${RAN_REMOTE_ETC_ROOT:-/etc/open-ran-agent}"
REMOTE_SYSTEMD_DIR="${RAN_REMOTE_SYSTEMD_DIR:-${REMOTE_INSTALL_ROOT}/systemd}"
INSTALL_LOG_ROOT="${RAN_INSTALL_LOG_ROOT:-$(pwd)/artifacts/install_runs}"
REMOTE_APPLY="${RAN_REMOTE_APPLY:-0}"

if [[ -n "${RAN_LOCAL_CONFIG_ROOT:-}" ]]; then
  LOCAL_CONFIG_ROOT="${RAN_LOCAL_CONFIG_ROOT}"
elif [[ -d "$(pwd)/artifacts/deploy_preview/etc" ]]; then
  LOCAL_CONFIG_ROOT="$(pwd)/artifacts/deploy_preview/etc"
else
  LOCAL_CONFIG_ROOT=""
fi

if [[ ! -f "${BUNDLE_TARBALL}" ]]; then
  echo "bundle tarball not found: ${BUNDLE_TARBALL}" >&2
  exit 66
fi

INSTALLER_PATH="$(cd "$(dirname "${BUNDLE_TARBALL}")" && pwd)/install_bundle.sh"

if [[ ! -f "${INSTALLER_PATH}" ]]; then
  echo "installer not found next to bundle: ${INSTALLER_PATH}" >&2
  exit 66
fi

SSH_TARGET="${TARGET_HOST}"
if [[ -n "${SSH_USER}" ]]; then
  SSH_TARGET="${SSH_USER}@${TARGET_HOST}"
fi

REMOTE_BUNDLE_TARBALL="${REMOTE_BUNDLE_DIR}/$(basename "${BUNDLE_TARBALL}")"
REMOTE_INSTALLER="${REMOTE_BUNDLE_DIR}/install_bundle.sh"
REMOTE_CURRENT="${REMOTE_INSTALL_ROOT}/current"
LOCAL_TOPOLOGY_FILE="${LOCAL_CONFIG_ROOT:+${LOCAL_CONFIG_ROOT}/topology.single_du.target_host.rfsim.json}"
LOCAL_REQUEST_FILE="${LOCAL_CONFIG_ROOT:+${LOCAL_CONFIG_ROOT}/requests/precheck-target-host.json}"
LOCAL_DASHBOARD_ENV_FILE="${LOCAL_CONFIG_ROOT:+${LOCAL_CONFIG_ROOT}/ran-dashboard.env}"
LOCAL_PREFLIGHT_ENV_FILE="${LOCAL_CONFIG_ROOT:+${LOCAL_CONFIG_ROOT}/ran-host-preflight.env}"
LOCAL_PROFILE_FILE="${LOCAL_CONFIG_ROOT:+${LOCAL_CONFIG_ROOT}/deploy.profile.json}"
LOCAL_EFFECTIVE_CONFIG_FILE="${LOCAL_CONFIG_ROOT:+${LOCAL_CONFIG_ROOT}/deploy.effective.json}"
LOCAL_READINESS_FILE="${LOCAL_CONFIG_ROOT:+${LOCAL_CONFIG_ROOT}/deploy.readiness.json}"
REMOTE_TOPOLOGY_FILE="${REMOTE_ETC_ROOT}/topology.single_du.target_host.rfsim.json"
REMOTE_REQUEST_FILE="${REMOTE_ETC_ROOT}/requests/precheck-target-host.json"
REMOTE_DASHBOARD_ENV_FILE="${REMOTE_ETC_ROOT}/ran-dashboard.env"
REMOTE_PREFLIGHT_ENV_FILE="${REMOTE_ETC_ROOT}/ran-host-preflight.env"
REMOTE_PROFILE_FILE="${REMOTE_ETC_ROOT}/deploy.profile.json"
REMOTE_EFFECTIVE_CONFIG_FILE="${REMOTE_ETC_ROOT}/deploy.effective.json"
REMOTE_READINESS_FILE="${REMOTE_ETC_ROOT}/deploy.readiness.json"
RUN_STAMP="$(date +%Y%m%dT%H%M%S)"
LOCAL_RUN_DIR="${INSTALL_LOG_ROOT}/${TARGET_HOST}/${RUN_STAMP}-ship"
LOCAL_PLAN_FILE="${LOCAL_RUN_DIR}/plan.txt"
LOCAL_TRANSCRIPT_FILE="${LOCAL_RUN_DIR}/transcript.log"
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
    "kind=ship_bundle" \
    "run_stamp=${RUN_STAMP}" \
    "target_host=${TARGET_HOST}" \
    "ssh_target=${SSH_TARGET}" \
    "bundle=${BUNDLE_TARBALL}" \
    "install_root=${REMOTE_INSTALL_ROOT}" \
    "etc_root=${REMOTE_ETC_ROOT}" \
    "sync_preview_config=${SYNC_PREVIEW_CONFIG}" \
    "plan_file=${LOCAL_PLAN_FILE}" \
    "transcript_file=${LOCAL_TRANSCRIPT_FILE}" \
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
  kind       : ship_bundle
  status     : ${RUN_STATUS}
  target host: ${TARGET_HOST}
  ssh target : ${SSH_TARGET}
  bundle     : ${BUNDLE_TARBALL}
  failed step: ${FAILED_STEP:-n/a}
  exit code  : ${EXIT_CODE:-n/a}

Inspect next:
  - summary   : ${LOCAL_DEBUG_SUMMARY_FILE}
  - plan      : ${LOCAL_PLAN_FILE}
  - transcript: ${LOCAL_TRANSCRIPT_FILE}
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

SYNC_PREVIEW_CONFIG=0
if [[ -n "${LOCAL_CONFIG_ROOT}" && -f "${LOCAL_TOPOLOGY_FILE}" && -f "${LOCAL_REQUEST_FILE}" && -f "${LOCAL_DASHBOARD_ENV_FILE}" && -f "${LOCAL_PREFLIGHT_ENV_FILE}" && -f "${LOCAL_PROFILE_FILE}" && -f "${LOCAL_EFFECTIVE_CONFIG_FILE}" && -f "${LOCAL_READINESS_FILE}" ]]; then
  SYNC_PREVIEW_CONFIG=1
fi

COMMANDS=(
  "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") mkdir -p $(quote "${REMOTE_BUNDLE_DIR}")"
  "scp -P $(quote "${SSH_PORT}") $(quote "${BUNDLE_TARBALL}") $(quote "${SSH_TARGET}:${REMOTE_BUNDLE_TARBALL}")"
  "scp -P $(quote "${SSH_PORT}") $(quote "${INSTALLER_PATH}") $(quote "${SSH_TARGET}:${REMOTE_INSTALLER}")"
  "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") env RAN_ETC_ROOT=$(quote "${REMOTE_ETC_ROOT}") RAN_SYSTEMD_STAGING_DIR=$(quote "${REMOTE_SYSTEMD_DIR}") bash $(quote "${REMOTE_INSTALLER}") $(quote "${REMOTE_BUNDLE_TARBALL}") $(quote "${REMOTE_INSTALL_ROOT}")"
)

if [[ "${SYNC_PREVIEW_CONFIG}" == "1" ]]; then
  COMMANDS+=(
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_TOPOLOGY_FILE}") $(quote "${SSH_TARGET}:${REMOTE_TOPOLOGY_FILE}")"
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_REQUEST_FILE}") $(quote "${SSH_TARGET}:${REMOTE_REQUEST_FILE}")"
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_DASHBOARD_ENV_FILE}") $(quote "${SSH_TARGET}:${REMOTE_DASHBOARD_ENV_FILE}")"
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_PREFLIGHT_ENV_FILE}") $(quote "${SSH_TARGET}:${REMOTE_PREFLIGHT_ENV_FILE}")"
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_PROFILE_FILE}") $(quote "${SSH_TARGET}:${REMOTE_PROFILE_FILE}")"
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_EFFECTIVE_CONFIG_FILE}") $(quote "${SSH_TARGET}:${REMOTE_EFFECTIVE_CONFIG_FILE}")"
    "scp -P $(quote "${SSH_PORT}") $(quote "${LOCAL_READINESS_FILE}") $(quote "${SSH_TARGET}:${REMOTE_READINESS_FILE}")"
    "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") env RAN_REPO_ROOT=$(quote "${REMOTE_CURRENT}") RAN_TOPOLOGY_FILE=$(quote "${REMOTE_TOPOLOGY_FILE}") RAN_PREFLIGHT_REQUEST=$(quote "${REMOTE_REQUEST_FILE}") $(quote "${REMOTE_CURRENT}/bin/ran-host-preflight")"
  )
else
  COMMANDS+=(
    "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") $(quote "${REMOTE_CURRENT}/bin/ran-deploy-wizard") --skip-install"
    "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") $(quote "${REMOTE_CURRENT}/bin/ran-host-preflight")"
  )
fi

{
  echo "Remote handoff plan for ${SSH_TARGET}"
  echo "  bundle   : ${BUNDLE_TARBALL}"
  echo "  installer: ${INSTALLER_PATH}"
  echo "  remote tmp: ${REMOTE_BUNDLE_DIR}"
  echo "  install root: ${REMOTE_INSTALL_ROOT}"
  echo "  config root : ${REMOTE_ETC_ROOT}"
  echo "  local preview: ${LOCAL_CONFIG_ROOT:-not detected}"
  echo "  log dir  : ${LOCAL_RUN_DIR}"
  echo
  echo "Commands:"
  for command in "${COMMANDS[@]}"; do
    echo "  ${command}"
  done
} | tee "${LOCAL_PLAN_FILE}" >/dev/null

if [[ "${REMOTE_APPLY}" == "1" ]]; then
  : > "${LOCAL_TRANSCRIPT_FILE}"
  for index in "${!COMMANDS[@]}"; do
    command="${COMMANDS[$index]}"

    case "${command}" in
      *install_bundle.sh*)
        CURRENT_STEP="remote_install"
        ;;
      *topology.single_du.target_host.rfsim.json*|*precheck-target-host.json*|*ran-dashboard.env*|*ran-host-preflight.env*|*deploy.profile.json*|*deploy.effective.json*|*deploy.readiness.json*)
        CURRENT_STEP="config_sync"
        ;;
      *ran-host-preflight*|*ran-deploy-wizard*)
        CURRENT_STEP="remote_preflight"
        ;;
      *)
        CURRENT_STEP="remote_stage"
        ;;
    esac

    CURRENT_COMMAND="${command}"
    echo "+ ${command}" | tee -a "${LOCAL_TRANSCRIPT_FILE}"
    eval "${command}" 2>&1 | tee -a "${LOCAL_TRANSCRIPT_FILE}"
  done
  CURRENT_COMMAND=""
  RUN_STATUS="applied"
else
  cat "${LOCAL_PLAN_FILE}"

  if [[ "${SYNC_PREVIEW_CONFIG}" == "1" ]]; then
    echo
    echo "Preview config files will be synced before remote preflight."
  else
    echo
    echo "Local preview config files were not detected; remote wizard/preflight commands are included instead."
  fi

  echo
  echo "After install/preflight, drive remote ranctl and fetch evidence with:"
  echo "  RAN_REMOTE_APPLY=1 ./bin/ran-remote-ranctl ${TARGET_HOST} precheck <request-file>"
  echo "  RAN_REMOTE_APPLY=1 ./bin/ran-fetch-remote-artifacts ${TARGET_HOST} <request-file>"
  echo "  Logs for this handoff are staged under ${LOCAL_RUN_DIR}"
  echo "  Debug pack is staged under ${LOCAL_DEBUG_PACK_FILE}"

  cat <<'EOF'

Set RAN_REMOTE_APPLY=1 to execute the commands instead of printing them.
EOF
fi
