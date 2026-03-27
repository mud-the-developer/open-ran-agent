#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: easy_install.sh [options]

Options:
  --bundle <tarball>           Explicit bundle tarball to use
  --deploy-profile <name>      Deploy profile. Default: stable_ops
  --target-host <host>         Remote host for handoff
  --ssh-user <user>            SSH username
  --ssh-port <port>            SSH port
  --apply                      Execute remote handoff instead of printing a plan
  --remote-precheck            After --apply, run remote ranctl precheck
  --force                      Bypass readiness gate for --apply
  --no-package-if-missing      Fail instead of packaging a new bundle when none exists
  -h, --help                   Show this help

Examples:
  bin/ran-install
  bin/ran-install --target-host ran-lab-01
  bin/ran-install --target-host ran-lab-01 --apply --remote-precheck
EOF
}

json_string_field() {
  local file="$1"
  local field="$2"

  tr -d '\n' < "${file}" \
    | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -n 1 \
    | sed -n "s/.*:[[:space:]]*\"\\([^\"]*\\)\"/\\1/p"
}

json_number_field() {
  local file="$1"
  local field="$2"

  tr -d '\n' < "${file}" \
    | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" \
    | head -n 1 \
    | sed -n "s/.*:[[:space:]]*\\([0-9][0-9]*\\)/\\1/p"
}

latest_bundle() {
  local latest=""
  local path

  shopt -s nullglob
  local bundles=("${REPO_ROOT}"/artifacts/releases/*/open_ran_agent-*.tar.gz)
  shopt -u nullglob

  if [[ ${#bundles[@]} -eq 0 ]]; then
    return 1
  fi

  for path in "${bundles[@]}"; do
    if [[ -z "${latest}" || "${path}" -nt "${latest}" ]]; then
      latest="${path}"
    fi
  done

  printf '%s\n' "${latest}"
}

package_bundle() {
  local bundle_id="easy-install-$(date +%Y%m%dT%H%M%S)"
  echo "+ mix ran.package_bootstrap --bundle-id ${bundle_id}"
  (
    cd "${REPO_ROOT}"
    mix ran.package_bootstrap --bundle-id "${bundle_id}"
  )
  printf '%s\n' "${REPO_ROOT}/artifacts/releases/${bundle_id}/open_ran_agent-${bundle_id}.tar.gz"
}

abspath() {
  local path="$1"
  printf '%s\n' "$(cd "$(dirname "${path}")" && pwd)/$(basename "${path}")"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
}

single_line() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g'
}

command_line() {
  local parts=()
  local arg

  for arg in "$@"; do
    parts+=("$(shell_quote "${arg}")")
  done

  printf '%s\n' "${parts[*]}"
}

write_text() {
  local path="$1"
  shift
  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "$@" > "${path}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_PROFILE="stable_ops"
TARGET_HOST=""
SSH_USER="${USER:-ranops}"
SSH_PORT="22"
APPLY="0"
REMOTE_PRECHECK="0"
FORCE="0"
PACKAGE_IF_MISSING="${RAN_INSTALL_PACKAGE_IF_MISSING:-1}"
BUNDLE_TARBALL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      BUNDLE_TARBALL="${2:-}"
      shift 2
      ;;
    --deploy-profile)
      DEPLOY_PROFILE="${2:-}"
      shift 2
      ;;
    --target-host)
      TARGET_HOST="${2:-}"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="${2:-}"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY="1"
      shift
      ;;
    --remote-precheck)
      REMOTE_PRECHECK="1"
      shift
      ;;
    --force)
      FORCE="1"
      shift
      ;;
    --no-package-if-missing)
      PACKAGE_IF_MISSING="0"
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

for cmd in bash sed tr grep head date mkdir; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "required command missing: ${cmd}" >&2
    exit 69
  fi
done

if [[ -n "${BUNDLE_TARBALL}" ]]; then
  BUNDLE_TARBALL="$(abspath "${BUNDLE_TARBALL}")"
elif bundle="$(latest_bundle)"; then
  BUNDLE_TARBALL="${bundle}"
elif [[ "${PACKAGE_IF_MISSING}" == "1" ]]; then
  if ! command -v mix >/dev/null 2>&1; then
    echo "mix is required to package a bundle when none exists" >&2
    exit 69
  fi

  BUNDLE_TARBALL="$(package_bundle)"
else
  echo "no bundle found under artifacts/releases and auto-packaging is disabled" >&2
  exit 66
fi

if [[ ! -f "${BUNDLE_TARBALL}" ]]; then
  echo "bundle tarball not found: ${BUNDLE_TARBALL}" >&2
  exit 66
fi

if [[ "${APPLY}" == "1" && -z "${TARGET_HOST}" ]]; then
  echo "--apply requires --target-host" >&2
  exit 64
fi

WIZARD_ARGS=(
  --json
  --defaults
  --safe-preview
  --skip-install
  --bundle "${BUNDLE_TARBALL}"
  --deploy-profile "${DEPLOY_PROFILE}"
)

if [[ -n "${TARGET_HOST}" ]]; then
  WIZARD_ARGS+=(--target-host "${TARGET_HOST}")
fi

if [[ -n "${SSH_USER}" ]]; then
  WIZARD_ARGS+=(--ssh-user "${SSH_USER}")
fi

if [[ -n "${SSH_PORT}" ]]; then
  WIZARD_ARGS+=(--ssh-port "${SSH_PORT}")
fi

RUN_STAMP="$(date +%Y%m%dT%H%M%S)"
QUICKSTART_DIR="${REPO_ROOT}/artifacts/deploy_preview/quick_install/${RUN_STAMP}"
WIZARD_RESULT_FILE="${QUICKSTART_DIR}/wizard-result.json"
SUMMARY_FILE="${QUICKSTART_DIR}/summary.txt"
REQUEST_FILE="${REPO_ROOT}/artifacts/deploy_preview/etc/requests/precheck-target-host.json"
PLAN_REQUEST_FILE="${REPO_ROOT}/artifacts/deploy_preview/etc/requests/plan-gnb-bringup.json"
VERIFY_REQUEST_FILE="${REPO_ROOT}/artifacts/deploy_preview/etc/requests/verify-attach-ping.json"
ROLLBACK_REQUEST_FILE="${REPO_ROOT}/artifacts/deploy_preview/etc/requests/rollback-gnb-cutover.json"
READINESS_FILE="${REPO_ROOT}/artifacts/deploy_preview/etc/deploy.readiness.json"
PROFILE_FILE="${REPO_ROOT}/artifacts/deploy_preview/etc/deploy.profile.json"
EFFECTIVE_CONFIG_FILE="${REPO_ROOT}/artifacts/deploy_preview/etc/deploy.effective.json"
PREVIEW_COMMAND_FILE="${QUICKSTART_DIR}/install.preview.sh"
APPLY_COMMAND_FILE="${QUICKSTART_DIR}/install.apply.sh"
REMOTE_PRECHECK_FILE="${QUICKSTART_DIR}/remote.precheck.sh"
REMOTE_LIFECYCLE_FILE="${QUICKSTART_DIR}/remote.lifecycle.sh"
REMOTE_FETCH_FILE="${QUICKSTART_DIR}/remote.fetch.sh"
GUIDE_FILE="${QUICKSTART_DIR}/INSTALL.md"
DEBUG_SUMMARY_FILE="${QUICKSTART_DIR}/debug-summary.txt"
DEBUG_PACK_FILE="${QUICKSTART_DIR}/debug-pack.txt"

mkdir -p "${QUICKSTART_DIR}"

CURRENT_STEP="wizard_preview"
CURRENT_COMMAND=""
RUN_STATUS="$(if [[ "${APPLY}" == "1" ]]; then echo applying; else echo prepared; fi)"
FAILED_STEP=""
FAILED_COMMAND=""
EXIT_CODE=""

write_debug_summary() {
  write_text \
    "${DEBUG_SUMMARY_FILE}" \
    "kind=quick_install" \
    "run_stamp=${RUN_STAMP}" \
    "target_host=${TARGET_HOST}" \
    "deploy_profile=${DEPLOY_PROFILE}" \
    "readiness_status=${READINESS_STATUS:-}" \
    "readiness_score=${READINESS_SCORE:-}" \
    "recommendation=${READINESS_RECOMMENDATION:-}" \
    "bundle=${BUNDLE_TARBALL}" \
    "request_file=${REQUEST_FILE}" \
    "readiness_file=${READINESS_FILE}" \
    "profile_file=${PROFILE_FILE}" \
    "effective_config_file=${EFFECTIVE_CONFIG_FILE}" \
    "wizard_result_file=${WIZARD_RESULT_FILE}" \
    "preview_command_file=${PREVIEW_COMMAND_FILE}" \
    "apply_command_file=${APPLY_COMMAND_FILE}" \
    "remote_precheck_file=${REMOTE_PRECHECK_FILE}" \
    "remote_lifecycle_file=${REMOTE_LIFECYCLE_FILE}" \
    "remote_fetch_file=${REMOTE_FETCH_FILE}" \
    "install_guide=${GUIDE_FILE}" \
    "debug_pack_file=${DEBUG_PACK_FILE}" \
    "failed_step=$(single_line "${FAILED_STEP}")" \
    "failed_command=$(single_line "${FAILED_COMMAND}")" \
    "exit_code=${EXIT_CODE}" \
    "status=${RUN_STATUS}"
}

write_debug_pack() {
  cat > "${DEBUG_PACK_FILE}" <<EOF
Debug Pack
  kind          : quick_install
  status        : ${RUN_STATUS}
  deploy profile: ${DEPLOY_PROFILE}
  target host   : ${TARGET_HOST:-not set}
  readiness     : ${READINESS_STATUS:-unknown}
  score         : ${READINESS_SCORE:-n/a}
  recommendation: ${READINESS_RECOMMENDATION:-n/a}
  failed step   : ${FAILED_STEP:-n/a}
  exit code     : ${EXIT_CODE:-n/a}

Inspect next:
  - summary        : ${DEBUG_SUMMARY_FILE}
  - readiness      : ${READINESS_FILE}
  - wizard result  : ${WIZARD_RESULT_FILE}
  - install guide  : ${GUIDE_FILE}
  - preview cmd    : ${PREVIEW_COMMAND_FILE}
  - apply cmd      : ${APPLY_COMMAND_FILE}
  - remote precheck: ${REMOTE_PRECHECK_FILE}
  - remote lifecycle: ${REMOTE_LIFECYCLE_FILE}
  - remote fetch   : ${REMOTE_FETCH_FILE}
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

CURRENT_COMMAND="$(command_line "${REPO_ROOT}/bin/ran-deploy-wizard" "${WIZARD_ARGS[@]}")"
WIZARD_OUTPUT="$("${REPO_ROOT}/bin/ran-deploy-wizard" "${WIZARD_ARGS[@]}")"
printf '%s\n' "${WIZARD_OUTPUT}" > "${WIZARD_RESULT_FILE}"
CURRENT_COMMAND=""

READINESS_STATUS="$(json_string_field "${READINESS_FILE}" "status")"
READINESS_RECOMMENDATION="$(json_string_field "${READINESS_FILE}" "recommendation")"
READINESS_SCORE="$(json_number_field "${READINESS_FILE}" "score")"

PREVIEW_COMMAND=(
  "bin/ran-install"
  "--bundle" "${BUNDLE_TARBALL}"
  "--deploy-profile" "${DEPLOY_PROFILE}"
)

if [[ -n "${TARGET_HOST}" ]]; then
  PREVIEW_COMMAND+=("--target-host" "${TARGET_HOST}")
fi

if [[ -n "${SSH_USER}" ]]; then
  PREVIEW_COMMAND+=("--ssh-user" "${SSH_USER}")
fi

if [[ -n "${SSH_PORT}" ]]; then
  PREVIEW_COMMAND+=("--ssh-port" "${SSH_PORT}")
fi

APPLY_COMMAND=("${PREVIEW_COMMAND[@]}" "--apply" "--remote-precheck")

write_text \
  "${PREVIEW_COMMAND_FILE}" \
  "#!/usr/bin/env bash" \
  "set -euo pipefail" \
  "" \
  "$(command_line "${PREVIEW_COMMAND[@]}")"

chmod +x "${PREVIEW_COMMAND_FILE}"

if [[ -n "${TARGET_HOST}" ]]; then
  write_text \
    "${APPLY_COMMAND_FILE}" \
    "#!/usr/bin/env bash" \
    "set -euo pipefail" \
    "" \
    "$(command_line "${APPLY_COMMAND[@]}")"

  write_text \
    "${REMOTE_PRECHECK_FILE}" \
    "#!/usr/bin/env bash" \
    "set -euo pipefail" \
    "" \
    "RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl $(shell_quote "${TARGET_HOST}") precheck $(shell_quote "${REQUEST_FILE}")"

  write_text \
    "${REMOTE_LIFECYCLE_FILE}" \
    "#!/usr/bin/env bash" \
    "set -euo pipefail" \
    "" \
    "RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl $(shell_quote "${TARGET_HOST}") precheck $(shell_quote "${REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl $(shell_quote "${TARGET_HOST}") plan $(shell_quote "${PLAN_REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl $(shell_quote "${TARGET_HOST}") apply $(shell_quote "${PLAN_REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl $(shell_quote "${TARGET_HOST}") verify $(shell_quote "${VERIFY_REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl $(shell_quote "${TARGET_HOST}") capture-artifacts $(shell_quote "${VERIFY_REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl $(shell_quote "${TARGET_HOST}") rollback $(shell_quote "${ROLLBACK_REQUEST_FILE}")"

  write_text \
    "${REMOTE_FETCH_FILE}" \
    "#!/usr/bin/env bash" \
    "set -euo pipefail" \
    "" \
    "RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts $(shell_quote "${TARGET_HOST}") $(shell_quote "${REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts $(shell_quote "${TARGET_HOST}") $(shell_quote "${PLAN_REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts $(shell_quote "${TARGET_HOST}") $(shell_quote "${VERIFY_REQUEST_FILE}")" \
    "RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts $(shell_quote "${TARGET_HOST}") $(shell_quote "${ROLLBACK_REQUEST_FILE}")"

  chmod +x "${APPLY_COMMAND_FILE}" "${REMOTE_PRECHECK_FILE}" "${REMOTE_LIFECYCLE_FILE}" "${REMOTE_FETCH_FILE}"
else
  write_text \
    "${APPLY_COMMAND_FILE}" \
    "# Set --target-host first to generate an executable remote install command."
  write_text \
    "${REMOTE_PRECHECK_FILE}" \
    "# Set --target-host first to generate an executable remote precheck command."
  write_text \
    "${REMOTE_LIFECYCLE_FILE}" \
    "# Set --target-host first to generate the full remote ranctl lifecycle helper."
  write_text \
    "${REMOTE_FETCH_FILE}" \
    "# Set --target-host first to generate the remote fetch helper."
fi

write_text \
  "${GUIDE_FILE}" \
  "# Easy Install" \
  "" \
  "- Bundle: ${BUNDLE_TARBALL}" \
  "- Deploy profile: ${DEPLOY_PROFILE}" \
  "- Target host: ${TARGET_HOST:-not set}" \
  "- Readiness: ${READINESS_STATUS:-unknown}" \
  "- Score: ${READINESS_SCORE:-n/a}" \
  "- Recommendation: ${READINESS_RECOMMENDATION:-n/a}" \
  "" \
  "Files:" \
  "- Preview command: ${PREVIEW_COMMAND_FILE}" \
  "- Apply command: ${APPLY_COMMAND_FILE}" \
  "- Remote precheck: ${REMOTE_PRECHECK_FILE}" \
  "- Remote lifecycle: ${REMOTE_LIFECYCLE_FILE}" \
  "- Remote fetch: ${REMOTE_FETCH_FILE}" \
  "- Request: ${REQUEST_FILE}" \
  "- Plan request: ${PLAN_REQUEST_FILE}" \
  "- Verify request: ${VERIFY_REQUEST_FILE}" \
  "- Rollback request: ${ROLLBACK_REQUEST_FILE}" \
  "- Readiness: ${READINESS_FILE}" \
  "- Profile: ${PROFILE_FILE}" \
  "- Effective config: ${EFFECTIVE_CONFIG_FILE}" \
  "- Wizard result: ${WIZARD_RESULT_FILE}"

{
  echo "Easy install summary"
  echo "  bundle        : ${BUNDLE_TARBALL}"
  echo "  deploy profile: ${DEPLOY_PROFILE}"
  echo "  target host   : ${TARGET_HOST:-not set}"
  echo "  readiness     : ${READINESS_STATUS:-unknown}"
  echo "  score         : ${READINESS_SCORE:-n/a}"
  echo "  recommendation: ${READINESS_RECOMMENDATION:-n/a}"
  echo "  request       : ${REQUEST_FILE}"
  echo "  profile       : ${PROFILE_FILE}"
  echo "  effective cfg : ${EFFECTIVE_CONFIG_FILE}"
  echo "  readiness file: ${READINESS_FILE}"
  echo "  wizard result : ${WIZARD_RESULT_FILE}"
  echo "  preview cmd   : ${PREVIEW_COMMAND_FILE}"
  echo "  apply cmd     : ${APPLY_COMMAND_FILE}"
  echo "  lifecycle cmd : ${REMOTE_LIFECYCLE_FILE}"
  echo "  fetch cmd     : ${REMOTE_FETCH_FILE}"
  echo "  install guide : ${GUIDE_FILE}"
  echo "  debug summary : ${DEBUG_SUMMARY_FILE}"
  echo "  debug pack    : ${DEBUG_PACK_FILE}"
  echo
  echo "Next:"
  echo "  1. Review ${READINESS_FILE}"

  if [[ -n "${TARGET_HOST}" ]]; then
    echo "  2. Run  bin/ran-ship-bundle ${BUNDLE_TARBALL} ${TARGET_HOST}"
    echo "  3. Run  bin/ran-remote-ranctl ${TARGET_HOST} precheck ${REQUEST_FILE}"
    echo "  4. Or   run ${REMOTE_LIFECYCLE_FILE} for the full replacement proof loop"
  else
    echo "  2. Set  --target-host to generate a real handoff plan"
    echo "  3. Or   run bin/ran-dashboard and continue from Deploy Studio"
  fi
} | tee "${SUMMARY_FILE}"

if [[ "${APPLY}" != "1" ]]; then
  echo
  echo "Dry-run only. Re-run with --apply to execute remote handoff."
  if [[ -n "${TARGET_HOST}" ]]; then
    echo "For the smallest full path, use:"
    echo "  bin/ran-install --target-host ${TARGET_HOST} --deploy-profile ${DEPLOY_PROFILE} --apply --remote-precheck"
  fi
  exit 0
fi

if [[ "${FORCE}" != "1" ]]; then
  case "${READINESS_STATUS}" in
    ready_for_preflight|ready_for_remote) ;;
    *)
      CURRENT_STEP="readiness_gate"
      CURRENT_COMMAND="apply readiness gate"
      mark_failure 65
      echo "refusing --apply because readiness is ${READINESS_STATUS:-unknown}; use --force to override" >&2
      echo "review ${READINESS_FILE}" >&2
      exit 65
      ;;
  esac
fi

CURRENT_STEP="remote_handoff"
CURRENT_COMMAND="$(command_line "${REPO_ROOT}/bin/ran-ship-bundle" "${BUNDLE_TARBALL}" "${TARGET_HOST}")"
env \
  RAN_SSH_USER="${SSH_USER}" \
  RAN_SSH_PORT="${SSH_PORT}" \
  RAN_REMOTE_APPLY=1 \
  "${REPO_ROOT}/bin/ran-ship-bundle" "${BUNDLE_TARBALL}" "${TARGET_HOST}"
CURRENT_COMMAND=""

if [[ "${REMOTE_PRECHECK}" == "1" ]]; then
  CURRENT_STEP="remote_precheck"
  CURRENT_COMMAND="$(command_line "${REPO_ROOT}/bin/ran-remote-ranctl" "${TARGET_HOST}" precheck "${REQUEST_FILE}")"
  env \
    RAN_SSH_USER="${SSH_USER}" \
    RAN_SSH_PORT="${SSH_PORT}" \
    RAN_REMOTE_APPLY=1 \
    "${REPO_ROOT}/bin/ran-remote-ranctl" "${TARGET_HOST}" precheck "${REQUEST_FILE}"
  CURRENT_COMMAND=""
fi

RUN_STATUS="applied"

cat <<EOF
Easy install completed
  summary       : ${SUMMARY_FILE}
  wizard result : ${WIZARD_RESULT_FILE}
  readiness file: ${READINESS_FILE}
  preview cmd   : ${PREVIEW_COMMAND_FILE}
  apply cmd     : ${APPLY_COMMAND_FILE}
  install guide : ${GUIDE_FILE}
  debug summary : ${DEBUG_SUMMARY_FILE}
  debug pack    : ${DEBUG_PACK_FILE}
EOF
