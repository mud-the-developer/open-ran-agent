# ranctl Action Model

## Role

`bin/ranctl` is the single mutable action entrypoint for operations. Skills, Symphony, Codex, and humans may request actions, but only `ranctl` turns intent into deterministic execution.

## Lifecycle

![ranctl lifecycle](../assets/figures/ranctl-lifecycle.svg)

<sub>Figure source: [../assets/infographics/ranctl-lifecycle.infographic](../assets/infographics/ranctl-lifecycle.infographic)</sub>

## Core Object Model

- `scope`: action scope such as `backend`, `cell_group`, `association`, or `incident`.
- `cell_group`: concrete DU-high target such as `cg-001`.
- `target_backend`: `stub_fapi_profile`, `local_fapi_profile`, or `aerial_fapi_profile`.
- `change_id`: immutable identifier for a planned change.
- `incident_id`: immutable identifier for an observed incident.
- `dry_run`: request planning without mutation.
- `ttl`: action validity window.
- `reason`: human or workflow justification.
- `idempotency_key`: deduplicates repeat submissions.
- `verify_window`: time budget and checks for post-apply verification.
- `max_blast_radius`: upper bound on service impact.
- `metadata.runtime_contract`: versioned release/runtime expectations for runtime-enabled lifecycle commands.

## Supported Commands

- `precheck`
- `plan`
- `apply`
- `verify`
- `rollback`
- `observe`
- `capture-artifacts`

## CLI Contract

`bin/ranctl` accepts:

- `--file PATH` to load a JSON request from disk
- `--json STRING` to pass a JSON request inline

Examples:

```bash
bin/ranctl plan --file examples/ranctl/precheck-switch-local.json
bin/ranctl apply --json '{"scope":"cell_group","cell_group":"cg-001","change_id":"chg-1","reason":"apply","idempotency_key":"chg-1","approval":{"approved":true,"approved_by":"operator","approved_at":"2026-03-21T07:00:00Z","ticket_ref":"CHG-1","source":"inline-example"},"verify_window":{"duration":"30s","checks":["gateway_healthy"]}}'
```

## JSON Request Shape

```json
{
  "scope": "cell_group",
  "cell_group": "cg-001",
  "target_backend": "local_fapi_profile",
  "change_id": "chg-20260320-001",
  "incident_id": null,
  "dry_run": false,
  "ttl": "15m",
  "reason": "switch backend after lab validation",
  "idempotency_key": "cg-001-switch-local-001",
  "verify_window": {
    "duration": "30s",
    "checks": ["gateway_healthy", "cell_group_attached", "ue_ping_ok"]
  },
  "max_blast_radius": "single_cell_group"
}
```

## Example Response Shape

```json
{
  "status": "planned",
  "command": "plan",
  "change_id": "chg-20260320-001",
  "summary": "backend switch prepared for cg-001",
  "next": ["apply", "verify"],
  "artifacts": ["plans/chg-20260320-001.json"]
}
```

## Artifact Paths

Bootstrap `ranctl` persists deterministic outputs under `artifacts/`:

- `artifacts/plans/<change_id>.json`
- `artifacts/changes/<change_id>.json`
- `artifacts/verify/<change_id>.json`
- `artifacts/captures/<incident_id-or-change_id>.json`
- `artifacts/rollback_plans/<change_id>.json`
- `artifacts/approvals/<change_id>-<command>.json`
- `artifacts/config_snapshots/<incident_id-or-change_id>.json`
- `artifacts/control_snapshots/<incident_id-or-change_id>.json`

For runtime-enabled changes, the plan, state, verify, and approval artifacts also carry a persisted `runtime_contract` snapshot with:

- `version`
- `release_unit`
- `release_ref`
- `entrypoint`
- resolved `runtime_mode`
- resolved `runtime_digest`
- `release_readiness`

## Execution Rules

- `precheck` must validate target existence, health, drain readiness, and config completeness.
- `plan` must produce an ordered action list plus rollback intent.
- `apply` must reject requests missing `change_id`, `reason`, or approval state when required.
- `verify` must use bounded checks with explicit failure criteria.
- `rollback` must restore the previous known-good target where possible.
- `observe` and `capture-artifacts` are read-oriented and may execute without change approval.

In the current bootstrap implementation, `precheck` also returns:

- a `config_report` from `ran_config` validation
- pass or fail status for `scope_valid`, `target_backend_known`, `verify_window_valid`, `config_shape_present`, and `cell_group_exists`
- `policy` details for controlled backend failover, including allowed targets and rollback target
- optional `control_state` details for attach freeze and drain workflow
- optional `native_probe` details when `metadata.native_probe` is present
- optional `runtime` details when `metadata.oai_runtime` is present

## OAI Runtime Extension

`ranctl` can now orchestrate an external OpenAirInterface DU stack without moving runtime hot paths into the BEAM. This path is enabled through `metadata.oai_runtime`.

Runtime-enabled lifecycle commands now also require `metadata.runtime_contract` so the release unit, entrypoint, release reference, and expected runtime mode are explicit on the control surface.

Example:

```json
{
  "metadata": {
    "runtime_contract": {
      "version": "ranctl.runtime.v1",
      "release_unit": "bootstrap_source_bundle",
      "release_ref": "source-checkout@cg-001",
      "entrypoint": "bin/ranctl",
      "runtime_mode": "docker_compose_rfsim_f1"
    },
    "oai_runtime": {
      "repo_root": "/opt/openairinterface5g",
      "du_conf_path": "/opt/openairinterface5g/ci-scripts/conf_files/gnb-du.sa.band78.106prb.rfsim.conf",
      "cucp_conf_path": "/opt/openairinterface5g/ci-scripts/conf_files/gnb-cucp.sa.f1.conf",
      "cuup_conf_path": "/opt/openairinterface5g/ci-scripts/conf_files/gnb-cuup.sa.f1.conf",
      "project_name": "ran-oai-du-cg-001",
      "pull_images": true
    }
  }
}
```

With this metadata:

- `precheck` and `plan` reject requests that omit `runtime_contract.version`, `release_unit`, `release_ref`, `entrypoint`, or `runtime_mode`
- `plan` persists a `runtime_contract` snapshot with the resolved runtime mode, runtime digest, and release-readiness snapshot
- `apply`, `verify`, and `rollback` reject runtime contract drift before touching runtime actions
- `plan` writes a generated Compose asset under `artifacts/runtime/<change_id>/docker-compose.yml`
- `plan` also writes patched overlay confs under `artifacts/runtime/<change_id>/conf/`
- source conf files remain untouched and are only used as overlay inputs
- `apply` runs `docker compose up -d` for `oai-cucp`, `oai-cuup`, and `oai-du`
- `precheck` validates split markers and required address patch points in the source confs
- `verify` inspects container liveness and captures log tails
- `rollback` runs `docker compose down -v --remove-orphans`

Reference examples:

- `examples/ranctl/precheck-oai-du-docker.json`
- `examples/ranctl/apply-oai-du-docker.json`
- `examples/ranctl/apply-oai-du-docker-template.json`
- `examples/ranctl/verify-oai-du-docker.json`
- `examples/ranctl/rollback-oai-du-docker.json`

## Approval Model

- Non-destructive reads: no explicit approval beyond repo policy.
- Mutations with no service impact: approval gate optional but auditable.
- Service-affecting actions: explicit approval required.
- Backend switch and drain actions: explicit approval required.

## Control-State Extension

`metadata.control` lets `ranctl` coordinate attach freeze and drain semantics without adding a second mutable entrypoint.

Example:

```json
{
  "metadata": {
    "control": {
      "attach_freeze": "activate",
      "drain": "start"
    }
  }
}
```

Supported verify and precheck checks:

- `attach_freeze_active`
- `drain_active`
- `cell_group_drained`
- `drain_idle`

`observe` now includes `control_state` plus `incident_summary` so dashboards and skills can render the same operator-facing incident brief.

## Native Probe Extension

`metadata.native_probe` lets `ranctl` open a bounded Port-backed backend session during `precheck` and `verify` without mutating the long-lived runtime.

Example:

```json
{
  "metadata": {
    "native_probe": {
      "backend_profile": "local_fapi_profile",
      "session_payload": {
        "fronthaul_session": "fh-precheck-001",
        "host_interface": "sync0",
        "strict_host_probe": true
      }
    }
  }
}
```

With this metadata:

- `precheck` opens a short-lived backend session, reads backend health, and attempts activation for a hard gate check
- `precheck` returns `native_probe` plus explicit checks for `native_probe_resolved`, `native_probe_host_ready`, and `native_probe_activation_gate_clear`
- `native_probe` also returns `handshake_target` and `probe_observations` so operators can see what the backend actually inspected on the host
- those observations now distinguish presence from readiness or bounded openability for bootstrap-safe host checks
- `verify` repeats the same bounded probe so post-apply validation can fail on missing host or device prerequisites
- `observe` can lift persisted probe failures into `incident_summary.reasons` and `suggested_next`
- `capture-artifacts` writes a deterministic probe snapshot under `artifacts/probe_snapshots/<change_id-or-incident_id>.json`

Reference example:

- `examples/ranctl/precheck-native-probe-local.json`
