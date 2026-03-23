# Control State And Artifact Retention

## Control State

Bootstrap operations now track a lightweight control-state snapshot per `cell_group`.

The current model records:

- `attach_freeze`: `inactive` or `active`
- `drain`: `idle`, `draining`, or `drained`
- `source_change_id`, `source_command`, `reason`, and `changed_at`

The state lives in the BEAM and is intended for bounded operational coordination, not long-term persistence.

## Request Contract

Control-state mutations are requested through `metadata.control`.

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

Supported intents:

- `attach_freeze`: `activate`, `release`
- `drain`: `start`, `complete`, `clear`

## Validation And Verify Checks

`precheck` and `verify` now understand these bounded checks:

- `attach_freeze_active`
- `drain_active`
- `cell_group_drained`
- `drain_idle`

This lets skills and operators gate backend work on explicit freeze and drain state without inventing separate ad hoc probes.

## Observe Contract

`observe` now returns:

- `control_state`
- `incident_summary.severity`
- `incident_summary.reasons`
- `incident_summary.suggested_next`

This is the repo-local incident brief that dashboard and skills can consume before a human decides to continue, rollback, or capture more evidence.

## Artifact Retention

Bootstrap artifact naming remains deterministic and append-only by reference id.

- change-scoped plans and state:
  - `artifacts/plans/<change_id>.json`
  - `artifacts/changes/<change_id>.json`
  - `artifacts/verify/<change_id>.json`
  - `artifacts/rollback_plans/<change_id>.json`
  - `artifacts/approvals/<change_id>-<command>.json`
- capture-scoped support artifacts:
  - `artifacts/captures/<incident_id-or-change_id>.json`
  - `artifacts/config_snapshots/<incident_id-or-change_id>.json`
  - `artifacts/control_snapshots/<incident_id-or-change_id>.json`
  - `artifacts/probe_snapshots/<incident_id-or-change_id>.json`

Retention policy is intentionally simple for bootstrap:

- never overwrite a different reference id
- rewrite the same reference id deterministically
- keep runtime logs and generated confs under `artifacts/runtime/<change_id>/`
- treat cleanup as an explicit operator action, not automatic garbage collection

Current explicit cleanup contract:

- `mix ran.prune_artifacts` plans retention without deleting anything
- `mix ran.prune_artifacts --apply` deletes only entries selected by the planner
- default keep limits:
  - JSON artifact refs: `20` per category
  - runtime directories: `8`
  - release bundle directories: `5`
- `artifacts/control_state/*` is protected by default and excluded from pruning

## Operator Debug Artifacts

Target-host staging and remote execution now also produce operator-facing debug bundles:

- `artifacts/deploy_preview/quick_install/<run_stamp>/debug-summary.txt`
- `artifacts/deploy_preview/quick_install/<run_stamp>/debug-pack.txt`
- `artifacts/install_runs/<host>/<run_stamp>-ship/debug-summary.txt`
- `artifacts/install_runs/<host>/<run_stamp>-ship/debug-pack.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/debug-summary.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/debug-pack.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/fetch/debug-summary.txt`
- `artifacts/remote_runs/<host>/<run_stamp>-<command>/fetch/debug-pack.txt`

These are not yet pruned by a separate policy. They live beside the run they describe so operators can inspect one directory and stop.

See [14-debug-and-evidence-workflow.md](14-debug-and-evidence-workflow.md) for the triage path that consumes them.
