# Debug And Evidence Workflow

## Goal

Give operators one short path from failure to evidence without forcing them to remember every artifact directory.

The current bootstrap goal is:

1. every deploy or remote run writes deterministic debug artifacts
2. the dashboard points to the newest failure
3. CLI users can jump to the same failure with one command

## Primary entrypoints

Use these first:

- `bin/ran-debug-latest`
- `bin/ran-debug-latest --failures-only`
- `bin/ran-install`
- `bin/ran-ship-bundle`
- `bin/ran-remote-ranctl`
- `bin/ran-fetch-remote-artifacts`
- `bin/ran-dashboard`

## Operator triage path

For the fastest path:

1. Run `bin/ran-debug-latest --failures-only`.
2. Open the reported `debug-pack.txt`.
3. Follow the `Inspect next` file list in that debug pack.
4. If the failure happened on a remote host, inspect the matching `command.log`, `result.jsonl`, and fetched evidence bundle.
5. If the failure happened before remote execution, inspect `deploy.readiness.json` and the generated helper commands.

## Artifact families

### Quick install

`bin/ran-install` writes:

- `artifacts/deploy_preview/quick_install/<run_stamp>/summary.txt`
- `artifacts/deploy_preview/quick_install/<run_stamp>/INSTALL.md`
- `artifacts/deploy_preview/quick_install/<run_stamp>/install.preview.sh`
- `artifacts/deploy_preview/quick_install/<run_stamp>/install.apply.sh`
- `artifacts/deploy_preview/quick_install/<run_stamp>/remote.precheck.sh`
- `artifacts/deploy_preview/quick_install/<run_stamp>/debug-summary.txt`
- `artifacts/deploy_preview/quick_install/<run_stamp>/debug-pack.txt`

Read these in order:

- `debug-pack.txt`
- `debug-summary.txt`
- `INSTALL.md`
- `wizard-result.json`
- `artifacts/deploy_preview/etc/deploy.readiness.json`

### Bundle handoff

`bin/ran-ship-bundle` writes:

- `artifacts/install_runs/<host>/<run_stamp>-ship/plan.txt`
- `artifacts/install_runs/<host>/<run_stamp>-ship/transcript.log`
- `artifacts/install_runs/<host>/<run_stamp>-ship/debug-summary.txt`
- `artifacts/install_runs/<host>/<run_stamp>-ship/debug-pack.txt`

This is the right place when `scp`, `ssh`, remote install, or remote preflight fails.

### Remote ranctl

`bin/ran-remote-ranctl` writes:

- `artifacts/remote_runs/<host>/<run_stamp>-<command>/plan.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/command.log`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/result.jsonl`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/debug-summary.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/debug-pack.txt`

If automatic fetchback is enabled, it also writes:

- `artifacts/remote_runs/<host>/<run_stamp>-<command>/fetch/plan.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/fetch/debug-summary.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/fetch/debug-pack.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/fetch/remote-evidence.tar.gz`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/fetch/extracted/*`

### Runtime evidence

Runtime-specific evidence remains under the existing artifact roots:

- `artifacts/prechecks/*`
- `artifacts/plans/*`
- `artifacts/changes/*`
- `artifacts/verify/*`
- `artifacts/captures/*`
- `artifacts/runtime/<change_id>/*`
- `artifacts/probe_snapshots/*`
- `artifacts/config_snapshots/*`
- `artifacts/control_snapshots/*`

## Debug summary contract

Each `debug-summary.txt` is a compact key-value file meant for machine indexing and shell use.

Typical fields:

- `kind`
- `status`
- `target_host`
- `deploy_profile`
- `command`
- `change_id`
- `incident_id`
- `failed_step`
- `failed_command`
- `exit_code`
- `plan_file`
- `result_file`
- `transcript_file` or `command_log`
- `debug_pack_file`

## Debug pack contract

Each `debug-pack.txt` is a human-first incident brief.

It should answer:

- what failed
- where it failed
- what command failed
- what file to open next

The `Inspect next` section is intentionally short so operators do not have to scan the whole artifact tree.

## Dashboard surfaces

`Deploy Studio` now exposes:

- `Install Debug Index`
- `Remote Run Index`
- `Latest Debug Incident`
- `Recent Debug Failures`

This is the UI equivalent of `bin/ran-debug-latest`.

Use the dashboard when:

- you want the newest failure without opening the filesystem first
- you want preview, readiness, handoff, and debug evidence in one place
- you want to compare multiple recent failures quickly

Use the CLI when:

- you are on a server without the dashboard running
- you are on SSH only
- you want a scriptable first-look workflow

## Common failure classes

### Readiness gate failure

Symptoms:

- `bin/ran-install --apply` refuses to continue
- readiness status is not `ready_for_preflight` or `ready_for_remote`

Inspect:

- `artifacts/deploy_preview/etc/deploy.readiness.json`
- latest quick-install `debug-pack.txt`

### Remote handoff failure

Symptoms:

- `scp` or `ssh` step fails
- bundle install does not complete remotely

Inspect:

- `artifacts/install_runs/<host>/<run_stamp>-ship/debug-pack.txt`
- `artifacts/install_runs/<host>/<run_stamp>-ship/transcript.log`

### Remote precheck or plan failure

Symptoms:

- remote `ranctl precheck` or `plan` returns non-ok status

Inspect:

- `artifacts/remote_runs/<host>/<run_stamp>-<command>/debug-pack.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/result.jsonl`
- fetched `prechecks`, `probe_snapshots`, `captures`, and config snapshots under `fetch/extracted`

### Native probe failure

Symptoms:

- `native_probe_host_ready` or `native_probe_activation_gate_clear` fails
- strict probe gate blocks activation

Inspect:

- `probe_snapshots/<change_or_incident_id>.json`
- `verify/<change_id>.json`
- fetched remote `config/deploy/deploy.readiness.json`

## Recommended operator loop

For day-to-day bring-up and rollback:

1. `bin/ran-install --target-host <host>`
2. `bin/ran-ship-bundle ... <host>`
3. `RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl <host> precheck <request-file>`
4. `RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl <host> plan <request-file>`
5. `RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl <host> apply <request-file>`
6. if anything fails, immediately run `bin/ran-debug-latest --failures-only`

## Current limits

- the debug workflow is strong for staging, preflight, contract execution, and evidence fetchback
- it does not replace backend-specific runtime debuggers
- attach-plus-ping still requires real target-host validation
- real `local_du_low` and `aerial` runtime integrations remain outside this bootstrap debug surface
