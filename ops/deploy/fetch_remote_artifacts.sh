#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: fetch_remote_artifacts.sh <target-host> [request-file]

Environment:
  RAN_SSH_USER             SSH username. Default: current user
  RAN_SSH_PORT             SSH port. Default: 22
  RAN_REMOTE_INSTALL_ROOT  Remote install root. Default: /opt/open-ran-agent
  RAN_REMOTE_ETC_ROOT      Remote config root. Default: /etc/open-ran-agent
  RAN_LOCAL_CONFIG_ROOT    Local preview config root. Default: ./artifacts/deploy_preview/etc when present
  RAN_REMOTE_APPLY         If set to 1, execute the remote fetch. Otherwise print the plan.
  RAN_REMOTE_RESULT_ROOT   Local result root. Default: ./artifacts/remote_runs
  RAN_REMOTE_OUTPUT_DIR    Explicit local output dir for the fetched archive and extraction
  RAN_REMOTE_FETCH_LABEL   Local nested-dir label when RAN_REMOTE_OUTPUT_DIR is not set
  RAN_REMOTE_FETCH_TMPDIR  Remote temp dir. Default: /tmp/open-ran-agent-fetch
  RAN_REMOTE_FETCH_CLEANUP Delete remote temp files after fetch. Default: 1
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

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 64
fi

for cmd in bash ssh scp sed tr tee date mkdir tar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "required command missing: ${cmd}" >&2
    exit 69
  fi
done

TARGET_HOST="$1"
REQUEST_FILE="${2:-}"

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
REMOTE_FETCH_TMPDIR="${RAN_REMOTE_FETCH_TMPDIR:-/tmp/open-ran-agent-fetch}"
REMOTE_FETCH_CLEANUP="${RAN_REMOTE_FETCH_CLEANUP:-1}"
REMOTE_APPLY="${RAN_REMOTE_APPLY:-0}"
RESULT_ROOT="${RAN_REMOTE_RESULT_ROOT:-$(pwd)/artifacts/remote_runs}"

SSH_TARGET="${TARGET_HOST}"
if [[ -n "${SSH_USER}" ]]; then
  SSH_TARGET="${SSH_USER}@${TARGET_HOST}"
fi

REMOTE_CURRENT="${REMOTE_INSTALL_ROOT}/current"
REMOTE_REQUEST_FILE="${REMOTE_ETC_ROOT}/requests/$(basename "${REQUEST_FILE}")"
REMOTE_TOPOLOGY_FILE="${REMOTE_ETC_ROOT}/topology.single_du.target_host.rfsim.json"
REMOTE_DASHBOARD_ENV_FILE="${REMOTE_ETC_ROOT}/ran-dashboard.env"
REMOTE_PREFLIGHT_ENV_FILE="${REMOTE_ETC_ROOT}/ran-host-preflight.env"
REMOTE_PROFILE_FILE="${REMOTE_ETC_ROOT}/deploy.profile.json"
REMOTE_EFFECTIVE_CONFIG_FILE="${REMOTE_ETC_ROOT}/deploy.effective.json"
REMOTE_READINESS_FILE="${REMOTE_ETC_ROOT}/deploy.readiness.json"

CHANGE_ID="$(json_field "${REQUEST_FILE}" "change_id")"
INCIDENT_ID="$(json_field "${REQUEST_FILE}" "incident_id")"
CELL_GROUP="$(json_field "${REQUEST_FILE}" "cell_group")"
TARGET_PROFILE="$(json_field "${REQUEST_FILE}" "target_profile")"
RUN_STAMP="$(date +%Y%m%dT%H%M%S)"
FETCH_LABEL="${RAN_REMOTE_FETCH_LABEL:-${RUN_STAMP}-fetch}"

if [[ -n "${RAN_REMOTE_OUTPUT_DIR:-}" ]]; then
  LOCAL_RUN_DIR="${RAN_REMOTE_OUTPUT_DIR}"
else
  LOCAL_RUN_DIR="${RESULT_ROOT}/${TARGET_HOST}/${FETCH_LABEL}"
fi

LOCAL_ARCHIVE="${LOCAL_RUN_DIR}/remote-evidence.tar.gz"
LOCAL_EXTRACT_DIR="${LOCAL_RUN_DIR}/extracted"
LOCAL_PLAN_FILE="${LOCAL_RUN_DIR}/plan.txt"
LOCAL_TRANSCRIPT_FILE="${LOCAL_RUN_DIR}/transcript.log"
LOCAL_DEBUG_SUMMARY_FILE="${LOCAL_RUN_DIR}/debug-summary.txt"
LOCAL_DEBUG_PACK_FILE="${LOCAL_RUN_DIR}/debug-pack.txt"
REMOTE_FETCH_ID="${CHANGE_ID:-${INCIDENT_ID:-${RUN_STAMP}}}"
REMOTE_STAGE_DIR="${REMOTE_FETCH_TMPDIR}/stage-${RUN_STAMP}"
REMOTE_ARCHIVE="${REMOTE_FETCH_TMPDIR}/remote-evidence-${REMOTE_FETCH_ID}.tar.gz"

mkdir -p "${LOCAL_RUN_DIR}"

CURRENT_STEP="plan"
CURRENT_COMMAND=""
RUN_STATUS="$(if [[ "${REMOTE_APPLY}" == "1" ]]; then echo applying; else echo planned; fi)"
FAILED_STEP=""
FAILED_COMMAND=""
EXIT_CODE=""

write_debug_summary() {
  printf '%s\n' \
    "kind=fetch_remote_artifacts" \
    "run_stamp=${RUN_STAMP}" \
    "target_host=${TARGET_HOST}" \
    "ssh_target=${SSH_TARGET}" \
    "request_file=${REQUEST_FILE}" \
    "change_id=${CHANGE_ID}" \
    "incident_id=${INCIDENT_ID}" \
    "cell_group=${CELL_GROUP}" \
    "target_profile=${TARGET_PROFILE}" \
    "archive=${LOCAL_ARCHIVE}" \
    "extract_dir=${LOCAL_EXTRACT_DIR}" \
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
  kind       : fetch_remote_artifacts
  status     : ${RUN_STATUS}
  target host: ${TARGET_HOST}
  change id  : ${CHANGE_ID:-n/a}
  incident id: ${INCIDENT_ID:-n/a}
  cell group : ${CELL_GROUP:-n/a}
  profile    : ${TARGET_PROFILE:-n/a}
  failed step: ${FAILED_STEP:-n/a}
  exit code  : ${EXIT_CODE:-n/a}

Inspect next:
  - summary   : ${LOCAL_DEBUG_SUMMARY_FILE}
  - plan      : ${LOCAL_PLAN_FILE}
  - transcript: ${LOCAL_TRANSCRIPT_FILE}
  - archive   : ${LOCAL_ARCHIVE}
  - extract   : ${LOCAL_EXTRACT_DIR}
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

REMOTE_COLLECT_SCRIPT="$(cat <<EOF
set -euo pipefail

stage_dir=$(quote "${REMOTE_STAGE_DIR}")
archive_path=$(quote "${REMOTE_ARCHIVE}")
current_root=$(quote "${REMOTE_CURRENT}")
request_file=$(quote "${REMOTE_REQUEST_FILE}")
topology_file=$(quote "${REMOTE_TOPOLOGY_FILE}")
dashboard_env_file=$(quote "${REMOTE_DASHBOARD_ENV_FILE}")
preflight_env_file=$(quote "${REMOTE_PREFLIGHT_ENV_FILE}")
profile_file=$(quote "${REMOTE_PROFILE_FILE}")
effective_config_file=$(quote "${REMOTE_EFFECTIVE_CONFIG_FILE}")
readiness_file=$(quote "${REMOTE_READINESS_FILE}")
change_id=$(quote "${CHANGE_ID}")
incident_id=$(quote "${INCIDENT_ID}")
cell_group=$(quote "${CELL_GROUP}")
target_profile=$(quote "${TARGET_PROFILE}")
run_stamp=$(quote "${RUN_STAMP}")
target_host=$(quote "${TARGET_HOST}")
copied=0

stage_copy() {
  local source="\$1"
  local relpath="\$2"
  local target="\${stage_dir}/\${relpath}"

  [[ -e "\${source}" ]] || return 0

  mkdir -p "\$(dirname "\${target}")"
  rm -rf "\${target}"
  cp -R "\${source}" "\${target}"
  copied=\$((copied + 1))
}

copy_matches() {
  local category="\$1"
  local needle="\$2"
  local base="\${current_root}/artifacts/\${category}"
  local pattern
  local path

  [[ -n "\${needle}" ]] || return 0
  [[ -d "\${base}" ]] || return 0

  pattern="\${base}/*\${needle}*"

  for path in \${pattern}; do
    if [[ -e "\${path}" ]]; then
      stage_copy "\${path}" "artifacts/\${category}/\$(basename "\${path}")"
    fi
  done
}

copy_replacement_phase() {
  local phase="\$1"
  local needle="\$2"
  local base="\${current_root}/artifacts/replacement/\${phase}"

  [[ -n "\${needle}" ]] || return 0
  [[ -d "\${base}" ]] || return 0

  if [[ -d "\${base}/\${needle}" ]]; then
    stage_copy "\${base}/\${needle}" "artifacts/replacement/\${phase}/\${needle}"
  fi
}

rm -rf "\${stage_dir}"
mkdir -p "\${stage_dir}"

for category in prechecks plans changes verify captures approvals rollback_plans probe_snapshots config_snapshots control_snapshots; do
  copy_matches "\${category}" "\${change_id}"
  copy_matches "\${category}" "\${incident_id}"
done

for phase in precheck plan apply observe verify capture rollback; do
  copy_replacement_phase "\${phase}" "\${change_id}"
done

if [[ -n "\${target_profile}" && -d "\${current_root}/artifacts/replacement/\${target_profile}" ]]; then
  stage_copy "\${current_root}/artifacts/replacement/\${target_profile}" "artifacts/replacement/\${target_profile}"
fi

if [[ -n "\${change_id}" && -d "\${current_root}/artifacts/runtime/\${change_id}" ]]; then
  stage_copy "\${current_root}/artifacts/runtime/\${change_id}" "artifacts/runtime/\${change_id}"
fi

stage_copy "\${request_file}" "config/requests/\$(basename "\${request_file}")"
stage_copy "\${topology_file}" "config/topology/\$(basename "\${topology_file}")"
stage_copy "\${dashboard_env_file}" "config/env/\$(basename "\${dashboard_env_file}")"
stage_copy "\${preflight_env_file}" "config/env/\$(basename "\${preflight_env_file}")"
stage_copy "\${profile_file}" "config/deploy/\$(basename "\${profile_file}")"
stage_copy "\${effective_config_file}" "config/deploy/\$(basename "\${effective_config_file}")"
stage_copy "\${readiness_file}" "config/deploy/\$(basename "\${readiness_file}")"

cat > "\${stage_dir}/fetch-summary.txt" <<SUMMARY
target_host=\${target_host}
change_id=\${change_id}
incident_id=\${incident_id}
cell_group=\${cell_group}
target_profile=\${target_profile}
request_file=\$(basename "\${request_file}")
copied_entries=\${copied}
generated_at=\${run_stamp}
SUMMARY

mkdir -p "\$(dirname "\${archive_path}")"
tar -czf "\${archive_path}" -C "\${stage_dir}" .
printf '%s\n' "\${archive_path}"
EOF
)"

COMMANDS=(
  "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") mkdir -p $(quote "${REMOTE_FETCH_TMPDIR}")"
  "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") bash -lc $(quote "${REMOTE_COLLECT_SCRIPT}")"
  "scp -P $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}:${REMOTE_ARCHIVE}") $(quote "${LOCAL_ARCHIVE}")"
)

if [[ "${REMOTE_FETCH_CLEANUP}" == "1" ]]; then
  COMMANDS+=(
    "ssh -p $(quote "${SSH_PORT}") $(quote "${SSH_TARGET}") rm -rf $(quote "${REMOTE_STAGE_DIR}") $(quote "${REMOTE_ARCHIVE}")"
  )
fi

{
  echo "Remote artifact fetch plan"
  echo "  target host : ${SSH_TARGET}"
  echo "  request file: ${REQUEST_FILE}"
  echo "  change_id   : ${CHANGE_ID:-n/a}"
  echo "  incident_id : ${INCIDENT_ID:-n/a}"
  echo "  output dir  : ${LOCAL_RUN_DIR}"
  echo "  archive     : ${LOCAL_ARCHIVE}"
  echo "  extract dir : ${LOCAL_EXTRACT_DIR}"
  echo
  echo "Commands:"
  for command in "${COMMANDS[@]}"; do
    echo "  ${command}"
  done
} | tee "${LOCAL_PLAN_FILE}" >/dev/null

if [[ "${REMOTE_APPLY}" != "1" ]]; then
  cat "${LOCAL_PLAN_FILE}"
  echo
  echo "Set RAN_REMOTE_APPLY=1 to execute the remote fetch."
  exit 0
fi

 : > "${LOCAL_TRANSCRIPT_FILE}"

for index in "${!COMMANDS[@]}"; do
  command="${COMMANDS[$index]}"
  CURRENT_COMMAND="${command}"

  if [[ "${index}" == "0" ]]; then
    CURRENT_STEP="prepare_remote_fetch"
  elif [[ "${index}" == "1" ]]; then
    CURRENT_STEP="collect_remote_artifacts"
  elif [[ "${index}" == "2" ]]; then
    CURRENT_STEP="download_archive"
  else
    CURRENT_STEP="cleanup_remote_fetch"
  fi

  echo "+ ${command}"
  eval "${command}" 2>&1 | tee -a "${LOCAL_TRANSCRIPT_FILE}"
done

CURRENT_COMMAND=""
CURRENT_STEP="extract_archive"
mkdir -p "${LOCAL_EXTRACT_DIR}"
tar -xzf "${LOCAL_ARCHIVE}" -C "${LOCAL_EXTRACT_DIR}"
RUN_STATUS="fetched"

cat <<EOF
Remote artifacts fetched
  output dir  : ${LOCAL_RUN_DIR}
  archive     : ${LOCAL_ARCHIVE}
  extract dir : ${LOCAL_EXTRACT_DIR}
  plan file   : ${LOCAL_PLAN_FILE}
  transcript  : ${LOCAL_TRANSCRIPT_FILE}
  debug pack  : ${LOCAL_DEBUG_PACK_FILE}
EOF
