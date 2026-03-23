# Open RAN Agent

Open RAN Agent is a bootstrap repository for a 5G SA RAN control and operations architecture centered on:

- CU-CP
- CU-UP
- DU-high
- split 7.2x southbound integration
- a native low-PHY / fronthaul runtime boundary
- deterministic operations through `bin/ranctl`

This repository is intentionally design-first. It defines system boundaries, OTP application boundaries, failure domains, southbound contracts, and operations workflows before implementing live RAN protocols or real-time data paths.

## Open Source Posture

This repository is prepared for public, open-source collaboration.

- license: [MIT](LICENSE)
- contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- security reporting: [SECURITY.md](SECURITY.md)
- only sanitized examples and templates belong in the repo
- private lab configs, generated artifacts, local crash dumps, and operator-specific OAI or srsRAN settings are intentionally ignored

If you maintain local lab files such as `OAI_config_WE_flexric.conf`, `srsran_config.yml`, or private OAI UE/gNB configs, keep them outside git or under ignored local-only filenames.

## Design Strategy

1. Use a Mix umbrella as the repo backbone so BEAM applications share tooling, config, and release conventions.
2. Keep BEAM responsible for control, orchestration, state management, and fault isolation.
3. Push slot-timed and fronthaul-adjacent work behind a native gateway boundary, starting with a Port-based sidecar.
4. Normalize DU-high southbound traffic through a canonical FAPI-oriented IR so local and Aerial-style backends share one contract.
5. Treat `bin/ranctl` as the only mutable action entrypoint for operational changes.
6. Keep Symphony, Codex, and skill workflows outside hot paths. They propose and orchestrate, but do not directly own runtime state transitions.
7. Design for single DU / single cell / single UE attach-plus-ping first, while reserving extension points for Aerial, cuMAC, and multi-cell work.
8. Record assumptions, open questions, and deferred decisions explicitly instead of hiding uncertainty in code.

## Proposed Repo Tree

```text
.
|-- AGENTS.md
|-- README.md
|-- bin/
|   |-- ran-debug-latest
|   |-- ran-install
|   |-- ranctl
|   |-- ran-dashboard
|   |-- ran-deploy-wizard
|   |-- ran-fetch-remote-artifacts
|   |-- ran-ship-bundle
|   |-- ran-remote-ranctl
|   `-- ran-host-preflight
|-- config/
|   |-- config.exs
|   |-- runtime.exs
|   |-- dev/
|   |   |-- README.md
|   |   `-- single_cell_local.exs.example
|   |-- lab/
|   |   |-- README.md
|   |   `-- single_cell_stub.exs.example
|   `-- prod/
|       |-- README.md
|       `-- controlled_failover.exs.example
|-- docs/
|   |-- adr/
|   `-- architecture/
|-- apps/
|   |-- ran_core/
|   |-- ran_cu_cp/
|   |-- ran_cu_up/
|   |-- ran_du_high/
|   |-- ran_fapi_core/
|   |-- ran_scheduler_host/
|   |-- ran_action_gateway/
|   |-- ran_observability/
|   |-- ran_config/
|   `-- ran_test_support/
|-- native/
|   |-- fapi_rt_gateway/
|   |-- local_du_low_adapter/
|   `-- aerial_adapter/
|-- ops/
|   |-- deploy/
|   |-- skills/
|   `-- symphony/
`-- examples/
    |-- incidents/
    `-- ranctl/
```

## Key Decisions

- Build structure: Mix umbrella with selective Erlang modules inside apps and native sidecars for RT-sensitive work.
- Language split: Elixir is the default for app boundaries, supervision, config, and ops layers; Erlang is reserved for protocol-heavy modules where it later proves advantageous.
- BEAM versus native boundary: `ran_du_high` talks to `ran_fapi_core`; `fapi_rt_gateway` handles backend transport and timing-sensitive bridging.
- Canonical southbound contract: `slot_batch`-oriented IR with backend capability negotiation and explicit health states.
- Scheduler abstraction: `ran_scheduler_host` owns the scheduler boundary; `cpu_scheduler` is the default implementation and `cumac_scheduler` remains a future adapter.
- Operations entrypoint: every mutating action must flow through `bin/ranctl` with `precheck -> plan -> apply -> verify -> rollback`.
- Failure domains: isolate `association`, `ue subtree`, `cell_group`, and `backend gateway`.
- Automation model: Symphony and Codex orchestrate skills; skills are thin wrappers around `bin/ranctl`; MCP is out of scope.

## Repository Guide

- Start with [docs/architecture/00-system-overview.md](docs/architecture/00-system-overview.md).
- Read ADRs in order under [docs/adr](docs/adr).
- Treat [bin/ranctl](bin/ranctl) as the future operational control surface.
- Use [AGENTS.md](AGENTS.md) for persistent repository rules.

Suggested reading order for operators:

1. [00-system-overview.md](docs/architecture/00-system-overview.md)
2. [05-ranctl-action-model.md](docs/architecture/05-ranctl-action-model.md)
3. [09-oai-du-runtime-bridge.md](docs/architecture/09-oai-du-runtime-bridge.md)
4. [12-target-host-deployment.md](docs/architecture/12-target-host-deployment.md)
5. [13-ocudu-inspired-ops-profiles.md](docs/architecture/13-ocudu-inspired-ops-profiles.md)
6. [14-debug-and-evidence-workflow.md](docs/architecture/14-debug-and-evidence-workflow.md)

Example:

```bash
bin/ranctl plan --file examples/ranctl/precheck-switch-local.json
```

Current bootstrap tests cover:

- `ranctl` lifecycle, approval handling, and config-aware prechecks
- `ran_du_high -> ran_scheduler_host -> ran_fapi_core -> stub backend`
- controlled failover policy based on configured `backend` and `failover_targets`
- reusable switch/rollback integration harness in `ran_test_support`
- OAI DU runtime orchestration through generated Docker Compose assets and mocked docker lifecycle checks
- thin skill wrapper scripts under `ops/skills/*/scripts/run.sh`
- native boundary placeholders such as `native/fapi_rt_gateway/PORT_PROTOCOL.md`

## Dashboard

`bin/ran-dashboard` starts a Symphony-style local dashboard for the repo's live RAN and agent surface.

- `http://127.0.0.1:4050/` serves the UI
- `http://127.0.0.1:4050/api/dashboard` returns the unified snapshot JSON
- `http://127.0.0.1:4050/api/health` returns the server health probe
- `http://127.0.0.1:4050/api/actions/run` accepts dashboard-triggered `ranctl` actions
- `http://127.0.0.1:4050/api/deploy/defaults` returns safe repo-local deploy defaults
- `http://127.0.0.1:4050/api/deploy/run` drives Deploy Studio preview and preflight runs

The dashboard pulls together:

- configured cell groups and backend policy from `ran_config`
- live Docker runtime state for OAI, DU split, UE, FlexRIC, xApps, and support services
- recent `plan/apply/verify/rollback/capture-artifacts` outputs from `artifacts/*`
- available operator skills from `ops/skills/*`
- target-host deploy preview state, rendered topology/request/env files, and preflight output
- deploy profile selection plus exported `deploy.profile.json` and `deploy.effective.json`
- exported `deploy.readiness.json` with rollout score, blockers, warnings, and recommendation
- remote handoff commands for `scp/ssh/install/preflight`
- recent remote host transcripts and fetched evidence under `artifacts/remote_runs/*`
- latest failed deploy/remote run with debug-pack pointers

The dashboard can now trigger a subset of `ranctl` commands directly from the UI:

- `observe`
- `precheck`
- `plan`
- `apply`
- `rollback`
- `capture-artifacts`

The dashboard also includes a `Deploy Studio` workspace that stages target-host files into
`artifacts/deploy_preview/*` by default, previews the rendered files before you touch
`/etc/open-ran-agent`, can run the same preflight path exposed by `bin/ran-deploy-wizard`,
lets operators choose an OCUDU-inspired deploy profile, exports `deploy.profile.json` and
`deploy.effective.json`, computes `deploy.readiness.json` for rollout gating, generates
remote handoff commands once `target_host` is set, and surfaces the latest remote `ranctl`
transcripts plus fetched evidence bundles. It now also exposes a `Debug Desk` view of the
latest failed install/remote run and the corresponding `debug-summary.txt` / `debug-pack.txt`
artifacts.

## Easy Install

`bin/ran-install` is now the shortest deploy entrypoint.

Example:

```bash
bin/ran-debug-latest --failures-only
bin/ran-install
bin/ran-install --target-host ran-lab-01
bin/ran-install --target-host ran-lab-01 --apply --remote-precheck
```

The command will:

- reuse the latest packaged bundle or build one if none exists
- generate safe preview files through `bin/ran-deploy-wizard`
- export `deploy.profile.json`, `deploy.effective.json`, and `deploy.readiness.json`
- write quickstart artifacts under `artifacts/deploy_preview/quick_install/*`
- write `debug-summary.txt` and `debug-pack.txt` beside each quick-install / ship / remote run
- optionally execute remote ship plus remote `ranctl precheck`
- refuse `--apply` unless readiness is cleared, unless `--force` is set

## Debug Quickstart

If an operator only needs the shortest failure-to-evidence path:

```bash
bin/ran-debug-latest --failures-only
bin/ran-install --target-host ran-lab-01
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 precheck ./artifacts/deploy_preview/etc/requests/precheck-target-host.json
```

Read these in order:

1. [14-debug-and-evidence-workflow.md](docs/architecture/14-debug-and-evidence-workflow.md)
2. `debug-pack.txt`
3. `debug-summary.txt`
4. `transcript.log` or `command.log`
5. fetched `result.jsonl` or `fetch/extracted/*`

Example:

```bash
bin/ran-dashboard
```

## CI

Use the shared local CI contract before pushing changes:

```bash
mix contract_ci
mix runtime_ci
mix ci
```

`mix contract_ci` is the fast design/contract gate. `mix runtime_ci` runs the tagged runtime smoke path and bootstrap packaging smoke. `mix ci` runs both. GitHub Actions mirrors the same split in `.github/workflows/ci.yml`.

GitHub Actions also uploads:

- architecture docs and ADR snapshot from the contract job
- `artifacts/releases/ci-smoke/**` plus runtime smoke artifacts from the runtime job

## Bootstrap Packaging

The repo now ships a source-first bootstrap bundle for lab-host style distribution.

```bash
mix ran.package_bootstrap
mix package_bootstrap
```

The command writes:

- `artifacts/releases/<bundle_id>/manifest.json`
- `artifacts/releases/<bundle_id>/open_ran_agent-<bundle_id>.tar.gz`

Packaging is stricter than normal bootstrap validation. It rejects topologies that do not declare controlled failover targets for each `cell_group`.

## Artifact Cleanup

Bootstrap artifact cleanup is explicit and dry-run first:

```bash
mix ran.prune_artifacts
mix prune_artifacts
mix ran.prune_artifacts --apply
```

The planner keeps recent JSON refs, recent runtime dirs, and recent release bundles, while protecting `artifacts/control_state/*` by default.

## Topology Override

The repo can now load a single-DU lab topology from `RAN_TOPOLOGY_FILE` before `ranctl` or the dashboard starts.

Example:

```bash
RAN_TOPOLOGY_FILE=config/lab/topology.single_du.rfsim.json bin/ranctl precheck --file examples/ranctl/precheck-oai-du-docker.json
RAN_TOPOLOGY_FILE=config/lab/topology.single_du.rfsim.json bin/ran-dashboard
```

The loaded topology path is surfaced in the dashboard snapshot and validation report.

## Control-State Workflows

`ranctl` now supports lightweight attach-freeze and drain coordination through `metadata.control`.

Examples:

```bash
bin/ranctl plan --file examples/ranctl/apply-freeze-attaches.json
bin/ranctl apply --file examples/ranctl/apply-freeze-attaches.json

bin/ranctl plan --file examples/ranctl/apply-drain-cell-group.json
bin/ranctl apply --file examples/ranctl/apply-drain-cell-group.json
bin/ranctl observe --file examples/ranctl/apply-drain-cell-group.json
bin/ranctl rollback --file examples/ranctl/rollback-drain-cell-group.json
```

`capture-artifacts` now writes config and control snapshots alongside the main capture bundle.

## OAI DU Runtime

The repo now includes an executable bridge from `ranctl` to a real OpenAirInterface DU runtime:

- runtime spec comes from `metadata.oai_runtime` and optional `cell_group` defaults
- `plan` renders `artifacts/runtime/<change_id>/docker-compose.yml`
- `plan` also renders patched overlay confs under `artifacts/runtime/<change_id>/conf/*.conf`
- `apply` brings up `CUCP + CUUP + DU` in RFsim F1 split mode
- `precheck` validates split markers and required patch points in the source confs
- `verify` inspects container state, captures log tails, and accepts steady-state DU activity for long-running containers
- `rollback` tears the stack down deterministically

Example:

```bash
bin/ranctl precheck --file examples/ranctl/precheck-oai-du-docker.json
bin/ranctl plan --file examples/ranctl/apply-oai-du-docker.json
bin/ranctl apply --file examples/ranctl/apply-oai-du-docker.json
bin/ranctl verify --file examples/ranctl/verify-oai-du-docker.json
bin/ranctl rollback --file examples/ranctl/rollback-oai-du-docker.json
```

To run against your own OAI conf set, replace the three `*_conf_path` fields in
`examples/ranctl/apply-oai-du-docker-template.json` and use the same metadata for
`precheck`, `plan`, `apply`, and `verify`.

See [docs/architecture/09-oai-du-runtime-bridge.md](docs/architecture/09-oai-du-runtime-bridge.md) for the current scope and limitations.

## Target Host Deploy

The bootstrap bundle now carries a target-host install and preflight chain:

- `ops/deploy/install_bundle.sh`
- `ops/deploy/ship_bundle.sh`
- `ops/deploy/run_remote_ranctl.sh`
- `ops/deploy/preflight.sh`
- `bin/ran-deploy-wizard`
- `bin/ran-fetch-remote-artifacts`
- `bin/ran-ship-bundle`
- `bin/ran-remote-ranctl`
- `bin/ran-host-preflight`
- `ops/deploy/systemd/ran-dashboard.service`
- `ops/deploy/systemd/ran-host-preflight.service`
- `config/prod/topology.single_du.target_host.rfsim.json.example`
- `examples/ranctl/precheck-target-host.json.example`

Target-host staging is now profile-driven. `bin/ran-deploy-wizard` and `Deploy Studio` can
render:

- `deploy.profile.json`
- `deploy.effective.json`

Available deploy profiles are:

- `stable_ops`
- `troubleshoot`
- `lab_attach`

Typical flow:

```bash
mix ran.package_bootstrap --bundle-id target-host-smoke
./artifacts/releases/target-host-smoke/install_bundle.sh ./artifacts/releases/target-host-smoke/open_ran_agent-target-host-smoke.tar.gz /opt/open-ran-agent
/opt/open-ran-agent/current/bin/ran-deploy-wizard --skip-install
/opt/open-ran-agent/current/bin/ran-host-preflight
```

Or start `bin/ran-dashboard` and use `Deploy Studio` to generate the same topology, request,
and env files into a safe repo-local preview root before moving them to the live host.

For remote handoff from the packaging host:

```bash
bin/ran-deploy-wizard --defaults --safe-preview --skip-install --target-host ran-lab-01
bin/ran-ship-bundle ./artifacts/releases/target-host-smoke/open_ran_agent-target-host-smoke.tar.gz ran-lab-01
RAN_REMOTE_APPLY=1 bin/ran-ship-bundle ./artifacts/releases/target-host-smoke/open_ran_agent-target-host-smoke.tar.gz ran-lab-01
RAN_REMOTE_APPLY=1 bin/ran-remote-ranctl ran-lab-01 precheck ./artifacts/deploy_preview/etc/requests/precheck-target-host.json
RAN_REMOTE_APPLY=1 bin/ran-fetch-remote-artifacts ran-lab-01 ./artifacts/deploy_preview/etc/requests/precheck-target-host.json
```

If `artifacts/deploy_preview/etc` exists, `bin/ran-ship-bundle` now syncs the rendered topology,
request, and env files to the remote host before running preflight. `bin/ran-remote-ranctl`
also auto-fetches matching remote evidence into `artifacts/remote_runs/*/fetch` unless
`RAN_REMOTE_FETCH=0` is set, and `bin/ran-fetch-remote-artifacts` can re-sync the same evidence
later on demand.

See [docs/architecture/12-target-host-deployment.md](docs/architecture/12-target-host-deployment.md) and [ops/deploy/README.md](ops/deploy/README.md).
The OCUDU-inspired reasoning for this model is captured in [docs/architecture/13-ocudu-inspired-ops-profiles.md](docs/architecture/13-ocudu-inspired-ops-profiles.md).

## Scope

In scope now:

- architecture documentation
- repo skeleton
- initial BEAM app boundaries
- canonical interfaces and stub modules
- operations workflow skeleton
- config examples
- backlog definition
- executable contract-only `ranctl` flow with file-backed plan, state, verify, and capture outputs
- end-to-end `stub_fapi_profile` path for boundary validation

Explicitly deferred:

- live ASN.1 codecs
- SCTP and GTP-U runtime stacks
- real eCPRI or O-RAN FH transport
- real local DU-low implementation
- real NVIDIA Aerial integration
- real cuMAC integration
- production Symphony hooks

## Assumptions

- SA-only deployment is sufficient for MVP.
- One DU, one cell group, and one UE path are enough to shape the initial contracts.
- RU-side low-PHY exists outside the BEAM core.
- Aerial integration can be represented through backend capabilities and profile selection without assuming internal Aerial implementation details.

## Next Steps

1. Fill in real app internals behind the current behaviours and structs.
2. Turn `bin/ranctl` from a bootstrap executor into a release-aware runtime entrypoint.
3. Replace the contract-only stub backend path with a real gateway-backed session path.
4. Add integration tests for backend switching, rollback, and artifact capture.
5. Initialize git history and CI once the design baseline is accepted.
