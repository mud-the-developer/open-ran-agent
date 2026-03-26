# Target Host Deploy

These files turn the bootstrap source bundle into a repeatable target-host install and preflight path.

## Files

- `bin/ran-deploy-wizard`: interactive guided setup for target-host topology, request, and env files
- `bin/ran-debug-latest`: print the latest debug run or latest failed run with the next files to inspect
- `bin/ran-install`: shortest install and remote handoff entrypoint
- `bin/ran-fetch-remote-artifacts`: dry-run or apply remote evidence fetch helper
- `bin/ran-ship-bundle`: dry-run or apply remote ssh/scp handoff helper
- `bin/ran-remote-ranctl`: dry-run or apply remote `ranctl` executor with local result capture
- `fetch_remote_artifacts.sh`: pulls matching remote artifacts and config snapshots back to the packaging host
- `install_bundle.sh`: unpacks a packaged bundle into an install root and stages env files
- `ship_bundle.sh`: prints or executes remote transfer/install/preflight commands
- `run_remote_ranctl.sh`: prints or executes remote `ranctl` commands and stores local transcripts
- `preflight.sh`: runs `bin/ranctl precheck` against a target-host request and optional topology file
- `systemd/ran-dashboard.service`: dashboard unit template
- `systemd/ran-host-preflight.service`: one-shot host preflight unit template

## Expected layout

- install root: `/opt/open-ran-agent`
- current symlink: `/opt/open-ran-agent/current`
- operator config root: `/etc/open-ran-agent`

All of these can be overridden with environment variables when running the install script.

## Minimal flow

1. Copy `open_ran_agent-<bundle_id>.tar.gz` and `install_bundle.sh` to the target host.
2. Run `./install_bundle.sh ./open_ran_agent-<bundle_id>.tar.gz /opt/open-ran-agent`.
3. Run `/opt/open-ran-agent/current/bin/ran-install`.
4. Or run `/opt/open-ran-agent/current/bin/ran-deploy-wizard --skip-install`.
5. Or use `Deploy Studio` inside `bin/ran-dashboard` to generate the same files under `artifacts/deploy_preview/*` first.
6. Or edit:
   - `/etc/open-ran-agent/topology.single_du.target_host.rfsim.json`
   - `/etc/open-ran-agent/requests/precheck-target-host.json`
   - `/etc/open-ran-agent/ran-dashboard.env`
   - `/etc/open-ran-agent/ran-host-preflight.env`
   - `/etc/open-ran-agent/deploy.profile.json`
   - `/etc/open-ran-agent/deploy.effective.json`
   - `/etc/open-ran-agent/deploy.readiness.json`
7. Run `/opt/open-ran-agent/current/bin/ran-host-preflight`.
8. Start `/opt/open-ran-agent/current/bin/ran-dashboard` or install the systemd unit templates.

## Fast debug flow

When something fails, do not start by browsing the whole artifact tree.

Use:

```bash
bin/ran-debug-latest --failures-only
```

Then inspect the files it reports in this order:

1. `debug-pack.txt`
2. `debug-summary.txt`
3. `transcript.log` or `command.log`
4. `result.jsonl`
5. fetched evidence under `fetch/extracted/*`

## Remote handoff

Dry-run the remote transfer and install commands:

```bash
bin/ran-install --target-host ran-lab-01
bin/ran-deploy-wizard --defaults --safe-preview --skip-install --target-host ran-lab-01
bin/ran-ship-bundle ./artifacts/releases/<bundle_id>/open_ran_agent-<bundle_id>.tar.gz ran-lab-01
```

If `artifacts/deploy_preview/etc` exists, the dry-run and apply paths also sync:

- `topology.single_du.target_host.rfsim.json`
- `requests/precheck-target-host.json`
- `requests/plan-gnb-bringup.json`
- `requests/verify-attach-ping.json`
- `requests/rollback-gnb-cutover.json`
- `ran-dashboard.env`
- `ran-host-preflight.env`
- `deploy.profile.json`
- `deploy.effective.json`
- `deploy.readiness.json`

The staging flow is profile-driven. Current profiles:

- `stable_ops`
- `troubleshoot`
- `lab_attach`

`bin/ran-deploy-wizard` and Deploy Studio now also compute a rollout readiness artifact that
includes a score, blockers, warnings, and the next recommended operator action.

`bin/ran-install` additionally writes:

- `artifacts/deploy_preview/quick_install/*/summary.txt`
- `artifacts/deploy_preview/quick_install/*/INSTALL.md`
- `artifacts/deploy_preview/quick_install/*/install.preview.sh`
- `artifacts/deploy_preview/quick_install/*/install.apply.sh`
- `artifacts/deploy_preview/quick_install/*/remote.precheck.sh`
- `artifacts/deploy_preview/quick_install/*/remote.lifecycle.sh`
- `artifacts/deploy_preview/quick_install/*/remote.fetch.sh`
- `artifacts/deploy_preview/quick_install/*/debug-summary.txt`
- `artifacts/deploy_preview/quick_install/*/debug-pack.txt`

and will refuse `--apply` unless readiness has reached `ready_for_preflight` or `ready_for_remote`,
unless `--force` is set.

Execute the same plan:

```bash
bin/ran-install --target-host ran-lab-01 --apply --remote-precheck
RAN_REMOTE_APPLY=1 bin/ran-ship-bundle ./artifacts/releases/<bundle_id>/open_ran_agent-<bundle_id>.tar.gz ran-lab-01
```

Run the declared remote lifecycle and store the local transcript under `artifacts/remote_runs/*`:

```bash
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 precheck ./artifacts/deploy_preview/etc/requests/precheck-target-host.json
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 plan ./artifacts/deploy_preview/etc/requests/plan-gnb-bringup.json
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 apply ./artifacts/deploy_preview/etc/requests/plan-gnb-bringup.json
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 verify ./artifacts/deploy_preview/etc/requests/verify-attach-ping.json
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 capture-artifacts ./artifacts/deploy_preview/etc/requests/verify-attach-ping.json
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 rollback ./artifacts/deploy_preview/etc/requests/rollback-gnb-cutover.json
```

`bin/ran-remote-ranctl` now auto-fetches matching remote evidence into
`artifacts/remote_runs/*/fetch` unless `RAN_REMOTE_FETCH=0` is set.
The fetchback bundle now mirrors any `artifacts/replacement/<phase>/<change_id>` proof tree alongside the core lifecycle artifacts.

Each `ship`, `remote ranctl`, and `fetch` run now also leaves:

- `debug-summary.txt`
- `debug-pack.txt`
- `transcript.log` or `command.log`

Use:

```bash
bin/ran-debug-latest --failures-only
```

to jump straight to the newest failed run and the relevant files.

Re-sync the same evidence later on demand:

```bash
RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts ran-lab-01 ./artifacts/deploy_preview/etc/requests/precheck-target-host.json
RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts ran-lab-01 ./artifacts/deploy_preview/etc/requests/plan-gnb-bringup.json
RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts ran-lab-01 ./artifacts/deploy_preview/etc/requests/verify-attach-ping.json
RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts ran-lab-01 ./artifacts/deploy_preview/etc/requests/rollback-gnb-cutover.json
```

## Artifact layout for debugging

The shortest mental model is:

- quick local staging: `artifacts/deploy_preview/quick_install/*`
- remote install and preflight: `artifacts/install_runs/<host>/*`
- remote ranctl execution: `artifacts/remote_runs/<host>/*`

Every family now leaves a compact debug pair:

- `debug-summary.txt`: machine-friendly key-value index
- `debug-pack.txt`: human-friendly next-step brief

Use [14-debug-and-evidence-workflow.md](../../docs/architecture/14-debug-and-evidence-workflow.md) for the full triage flow.
