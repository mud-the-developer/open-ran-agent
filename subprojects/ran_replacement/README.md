# OAI CU/DU Replacement Track

This subproject is a design-first workbench for a clean-room `CU/DU replacement` track that can eventually replace the operator-visible role currently filled by `OAI NR CU/DU`.

The replacement claim here is strict:

- implement the target-profile `OAI`-visible `CU/DU` function chain
- interoperate with a real `Open5GS` core
- keep declared external interfaces standards-correct for the supported scope

## Public-Surface Compatibility Profile

The milestone-3 planning baseline for operator-visible compatibility is:

- `open5gs_public_surface_ran_visible_v1`

This compatibility profile is broader than the milestone standards-subset
claims. It names the repo-visible NF set and external/operator-facing I/O
surfaces that must remain explicit while the narrower standards subset continues
to govern what the replacement lane can honestly claim as implemented today.

The target is intentionally narrow and physical:

- one `n79` lab profile first
- one real RU first
- one real UE first
- one real `Open5GS` core first
- one `attach + ping` success path first
- all mutable actions still routed through `bin/ranctl`

The immediate work here is not runtime code. The immediate work is:

- freeze the target lab profile and acceptance criteria
- define the operator and agent control surface
- define how the replacement lane interoperates with a real `Open5GS` core
- define ownership across `S`, `M`, `C`, and `U` plane concerns
- make BEAM versus native versus external boundaries explicit
- define `precheck -> plan -> apply -> verify -> rollback -> capture-artifacts` for replacement-track scopes
- describe how a staged cutover can happen without hiding rollback or evidence

The current document split is deliberate:

- notes `05` through `12` are the milestone-2 standards-baseline inputs
- notes `13` through `16` are the milestone-3 live-lab validation and
  operator-facing evidence inputs

## Quick Validation

Use the same contract validator locally that the repo-visible workflow runs:

```bash
npm run contracts:ran-replacement
```

That target delegates to [scripts/validate_contracts.sh](scripts/validate_contracts.sh) and validates:

- ranctl request fixtures
- status fixtures
- compare-report and rollback-evidence artifacts
- target-profile and lab-owner overlay examples
- package-local request/status fixtures

## Current Deliverables

- [task.md](task.md)
- [AGENTS.md](AGENTS.md)
- [../../docs/adr/0007-ran-functions-as-agent-friendly-cli-surface.md](../../docs/adr/0007-ran-functions-as-agent-friendly-cli-surface.md)
- [notes/00-target-profile-n79-lab.md](notes/00-target-profile-n79-lab.md)
- [notes/01-ran-function-cli-taxonomy.md](notes/01-ran-function-cli-taxonomy.md)
- [notes/02-boundaries-and-protocol-ownership.md](notes/02-boundaries-and-protocol-ownership.md)
- [notes/03-target-host-readiness-and-lab-gates.md](notes/03-target-host-readiness-and-lab-gates.md)
- [notes/04-open5gs-core-and-s-m-c-u-plane-scope.md](notes/04-open5gs-core-and-s-m-c-u-plane-scope.md)
- [notes/05-oai-function-and-standards-baseline.md](notes/05-oai-function-and-standards-baseline.md)
- [notes/06-ngap-and-registration-standards-subset.md](notes/06-ngap-and-registration-standards-subset.md)
- [notes/07-f1-c-and-e1ap-standards-subset.md](notes/07-f1-c-and-e1ap-standards-subset.md)
- [notes/08-f1-u-and-gtpu-standards-subset.md](notes/08-f1-u-and-gtpu-standards-subset.md)
- [notes/09-ngap-procedure-support-matrix.md](notes/09-ngap-procedure-support-matrix.md)
- [notes/10-f1-c-and-e1ap-procedure-support-matrix.md](notes/10-f1-c-and-e1ap-procedure-support-matrix.md)
- [notes/11-f1-u-and-gtpu-procedure-support-matrix.md](notes/11-f1-u-and-gtpu-procedure-support-matrix.md)
- [notes/12-standards-evidence-and-acceptance-gates.md](notes/12-standards-evidence-and-acceptance-gates.md)
- [notes/13-milestone-1-acceptance-runbook.md](notes/13-milestone-1-acceptance-runbook.md)
- [notes/14-compare-report-and-rollback-evidence-templates.md](notes/14-compare-report-and-rollback-evidence-templates.md)
- [notes/15-dashboard-fixture-mapping.md](notes/15-dashboard-fixture-mapping.md)
- [notes/16-milestone-3-live-lab-validation-lanes.md](notes/16-milestone-3-live-lab-validation-lanes.md)
- [notes/README.md](notes/README.md)
- [contracts/README.md](contracts/README.md)
- [contracts/n79-single-ru-target-profile-v1.schema.json](contracts/n79-single-ru-target-profile-v1.schema.json)
- [contracts/n79-single-ru-target-profile-overlay-v1.schema.json](contracts/n79-single-ru-target-profile-overlay-v1.schema.json)
- [contracts/examples/n79-single-ru-target-profile-v1.example.json](contracts/examples/n79-single-ru-target-profile-v1.example.json)
- [contracts/examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json](contracts/examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json)
- [packages/README.md](packages/README.md)
- [packages/ngap_edge/README.md](packages/ngap_edge/README.md)
- [packages/ngap_edge/CONTRACT.md](packages/ngap_edge/CONTRACT.md)
- [packages/f1e1_control_edge/README.md](packages/f1e1_control_edge/README.md)
- [packages/f1e1_control_edge/CONTRACT.md](packages/f1e1_control_edge/CONTRACT.md)
- [packages/user_plane_edge/README.md](packages/user_plane_edge/README.md)
- [packages/target_host_edge/README.md](packages/target_host_edge/README.md)
- [packages/target_host_edge/CONTRACT.md](packages/target_host_edge/CONTRACT.md)
- [packages/core_link_edge/README.md](packages/core_link_edge/README.md)
- [examples/ranctl/README.md](examples/ranctl/README.md)
- [examples/status/README.md](examples/status/README.md)
- [examples/artifacts/README.md](examples/artifacts/README.md)
- [examples/incidents/README.md](examples/incidents/README.md)
- [scripts/validate_contracts.sh](scripts/validate_contracts.sh)

## Immediate Non-Goals

- claiming parity with all OAI features
- replacing the core with an Elixir-native core in this track
- changing slot-paced hot paths today
- shipping a private-lab-specific config set into git
- bypassing the existing `ranctl` model with ad hoc helper scripts

## Replacement Rule

If a milestone cannot honestly say "the replacement lane owns the required target-profile `CU/DU` behavior and the declared external interfaces behave standards-correctly for that scope", then it is not yet a replacement milestone.
