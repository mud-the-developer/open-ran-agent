# Target Host Deployment

## Goal

Make the bootstrap source bundle movable to a real lab or operations host with a deterministic install and preflight path.

## Current deploy unit

The current repo still packages a `bootstrap_source_bundle`, but it now carries a target-host deploy chain:

- `bin/ran-install`
- `bin/ran-debug-latest`
- `bin/ran-deploy-wizard`
- `bin/ran-fetch-remote-artifacts`
- `bin/ran-ship-bundle`
- `bin/ran-remote-ranctl`
- `ops/deploy/fetch_remote_artifacts.sh`
- `ops/deploy/install_bundle.sh`
- `ops/deploy/ship_bundle.sh`
- `ops/deploy/run_remote_ranctl.sh`
- `ops/deploy/preflight.sh`
- `ops/deploy/systemd/ran-dashboard.service`
- `ops/deploy/systemd/ran-host-preflight.service`
- `config/prod/topology.single_du.target_host.rfsim.json.example`
- `examples/ranctl/precheck-target-host.json.example`

## Expected host layout

- install root: `/opt/open-ran-agent`
- current checkout symlink: `/opt/open-ran-agent/current`
- operator config root: `/etc/open-ran-agent`
- staged systemd units: `/opt/open-ran-agent/systemd`

## Host flow

1. Build a bundle with `mix ran.package_bootstrap --bundle-id <bundle_id>`.
2. Copy `open_ran_agent-<bundle_id>.tar.gz` and `install_bundle.sh` to the target host.
3. Run `./install_bundle.sh ./open_ran_agent-<bundle_id>.tar.gz /opt/open-ran-agent`.
4. Run `/opt/open-ran-agent/current/bin/ran-install` for the easiest setup path.
5. Or run `/opt/open-ran-agent/current/bin/ran-deploy-wizard --skip-install` for the guided setup path.
6. Or open `bin/ran-dashboard` and use `Deploy Studio` to preview the same files under `artifacts/deploy_preview/*` before touching host paths.
7. Or edit:
   - `/etc/open-ran-agent/topology.single_du.target_host.rfsim.json`
   - `/etc/open-ran-agent/requests/precheck-target-host.json`
   - `/etc/open-ran-agent/ran-dashboard.env`
   - `/etc/open-ran-agent/ran-host-preflight.env`
   - `/etc/open-ran-agent/deploy.profile.json`
   - `/etc/open-ran-agent/deploy.effective.json`
   - `/etc/open-ran-agent/deploy.readiness.json`
8. Run `/opt/open-ran-agent/current/bin/ran-host-preflight`.
9. Start `/opt/open-ran-agent/current/bin/ran-dashboard` or install the staged systemd units.

## Remote handoff path

From the packaging host, operators can now render a bounded remote handoff plan:

1. Run `bin/ran-install --target-host <host>` for the shortest path.
2. Or run `bin/ran-deploy-wizard --defaults --skip-install --target-host <host>` or use Deploy Studio.
   - use `--safe-preview` on the packaging host to stage files under `artifacts/deploy_preview/*` instead of `/etc/open-ran-agent`
   - choose a deploy profile such as `stable_ops`, `troubleshoot`, or `lab_attach`
   - review `deploy.readiness.json` before you hand the bundle to a remote host
   - review `artifacts/deploy_preview/quick_install/*/INSTALL.md` and the generated `install.*.sh` helpers
3. Review the generated `scp` and `ssh` commands.
4. Run `bin/ran-ship-bundle <bundle-tarball> <host>` for a dry-run summary.
   - when `artifacts/deploy_preview/etc` exists, the handoff also syncs topology, request, and env files to the remote config root
5. Set `RAN_REMOTE_APPLY=1` to execute the transfer and remote install steps.
6. Use `RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl <host> precheck|plan|apply|verify <request-file>` to drive remote `ranctl`, capture stdout locally under `artifacts/remote_runs/*`, and auto-fetch matching remote evidence into `artifacts/remote_runs/*/fetch`.
7. Use `RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts <host> <request-file>` to re-sync remote evidence on demand.
8. Use `bin/ran-debug-latest --failures-only` to jump to the newest failed install/remote run and its `debug-summary.txt` / `debug-pack.txt`.

For the detailed failure triage path, see [14-debug-and-evidence-workflow.md](14-debug-and-evidence-workflow.md).

## Scope

This path is enough for:

- moving the repo bundle to a real host
- loading a host-specific topology file
- running a bounded native and OAI precheck on that host
- bringing up the dashboard with host-specific env vars
- previewing deploy files and preflight output from the dashboard via `/api/deploy/*`
- exporting a profile manifest and effective merged config before remote handoff
- exporting a readiness artifact with rollout score, blockers, warnings, and recommendation
- exporting quickstart command files and an install guide for operator handoff
- exporting debug summaries, debug packs, and transcripts beside each install or remote run
- generating remote `scp/ssh/install/preflight` commands for a target host
- mirroring target-host artifacts, runtime evidence, and config snapshots back to the packaging host

This path is not yet:

- a compiled BEAM release
- a container image distribution flow
- a full UE attach plus ping validation
