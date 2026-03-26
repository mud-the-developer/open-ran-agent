# Production Control, Evidence, And Interoperability Lanes

## Goal

Make the current production-facing control, deploy, evidence, and recovery
posture explicit without overstating runtime or interoperability support that
still belongs to future work.

This document is the milestone-4 posture layer. It ties together the repo's
existing control/evidence surfaces and names which interoperability lanes are
reviewable today versus which still need more proof before they can be claimed
as supported.

## Hardened Now

The repo already has a production-facing operator loop for mutation control and
evidence review. The current hardened claim is about the control and evidence
surface, not full protocol-stack parity.

### Mutable control and approval surface

- `bin/ranctl` remains the only mutable action entrypoint.
- `precheck -> plan -> apply -> verify -> rollback -> capture-artifacts` is the
  explicit lifecycle for operational changes.
- approval, rollback intent, control-state gating, runtime contract snapshots,
  and bounded host probes are first-class request/response concepts.

Primary references:

- [05-ranctl-action-model](./05-ranctl-action-model.md)
- [11-control-state-and-artifact-retention](./11-control-state-and-artifact-retention.md)

### Target-host deploy, fetchback, and recovery loop

The repo now exposes a reviewable target-host path instead of a packaging-only
bootstrap story:

1. package and preview the source bundle
2. run host preflight and readiness scoring
3. ship the bundle or use the generated handoff helpers
4. execute remote `ranctl`
5. fetch evidence back into deterministic local artifact roots
6. inspect the latest failure through `bin/ran-debug-latest` or Deploy Studio

Primary references:

- [12-target-host-deployment](./12-target-host-deployment.md)
- [14-debug-and-evidence-workflow](./14-debug-and-evidence-workflow.md)

### Evidence families reviewers can inspect now

The current hardened evidence surface includes:

- `artifacts/deploy_preview/*` for preview, readiness, and quick-install output
- `artifacts/install_runs/*` for remote ship/install transcripts and summaries
- `artifacts/remote_runs/*` for remote `ranctl` plans, command logs, and fetches
- `artifacts/changes/*`, `artifacts/verify/*`, `artifacts/captures/*`, and
  `artifacts/rollback_plans/*` for action-level decision evidence
- `artifacts/runtime/*`, `artifacts/probe_snapshots/*`,
  `artifacts/config_snapshots/*`, and `artifacts/control_snapshots/*` for
  runtime, host, config, and control-state context

These artifact families are current support claims. Reviewers should not have
to infer deploy, verify, or rollback state from hidden operator memory.

### Replacement-track contract and evidence posture

`subprojects/ran_replacement/` is still design-first, but it now contributes a
reviewable control/evidence layer:

- request and status schemas for `ranctl` replacement scopes
- compare-report and rollback-evidence schemas
- sanitized status and artifact fixtures
- target-profile and core-link contracts for the declared `n79` plus real
  `Open5GS` lane

These are hardened as contract and evidence surfaces. They do not, by
themselves, claim that runtime cutover is already supported.

## Current Support Categories

| Category | Current claim | Evidence reviewers can expect now |
| --- | --- | --- |
| Production-facing control | Hardened now | `ranctl` lifecycle, approval rules, rollback intent, control-state checks |
| Deploy and recovery operations | Hardened now | target-host preview, remote execution, fetchback, debug summaries, debug packs |
| Replacement-track evidence contracts | Hardened now | schema-backed status, compare-report, rollback-evidence, target-profile fixtures |
| Live replacement runtime cutover | Future lane | real target-host attach-plus-ping proof on the declared lane |
| Aerial backend runtime | Future lane | vendor-independent adapter contract exists, but no supported runtime path yet |
| cuMAC scheduler integration | Future lane | scheduler boundary exists, but no supported external worker path yet |
| Broader interoperability profiles | Future lane | current contracts stay fixed to the declared `n79` plus real `Open5GS` scope; no multi-cell, multi-DU, or broad profile parity claim yet |

## Future Interoperability Lanes

These lanes remain explicit future work. They should stay reviewable as roadmap
lanes, not be described as current support.

| Lane | Current repo posture | What must be proven before support claims expand |
| --- | --- | --- |
| `Aerial` backend | Contract-only native adapter boundary plus host/device probe scaffolding; roadmap-only clean-room profile | target-host deploy path, verify/rollback evidence, stable runtime health model, and declared-profile evidence without claiming vendor device bring-up, attach-plus-ping proof, or production timing before that proof exists |
| `cuMAC` scheduler | Scheduler host boundary and future adapter placeholder; roadmap-only contract host | external worker contract, failure-domain evidence, cutover/rollback coverage, and proof that scheduler ownership stays bounded without claiming attach validation or runtime timing before that evidence exists |
| Broader RU/core/profile support | Current replacement contracts stay fixed to one `n79` / one real RU / one real UE / one real `Open5GS` core | a declared target profile, explicit core-link contract, schema-backed fixtures, and attach-plus-ping plus rollback evidence for that exact lane |
| Multi-cell or multi-DU orchestration | Mentioned in roadmap only | action scope, blast-radius rules, approval model, and evidence/rollback semantics for each additional scope before any multi-cell or multi-DU parity claim is allowed |

## Reviewer Rules

- Treat the current hardened claim as an operator-surface claim: control,
  deploy, evidence, and recovery are explicit and reviewable now.
- Treat replacement-track schemas and fixtures as evidence-model hardening, not
  as proof of live replacement runtime ownership.
- Treat `Aerial`, `cuMAC`, and broader interoperability profiles as future lanes
  until they have declared target profiles, repo-visible validation, and
  deterministic rollback evidence.
- Treat `aerial_fapi_profile` specifically as a roadmap-only clean-room adapter
  until host-probe evidence, target-host execution, and stable runtime health
  are reviewable without relying on vendor-internal claims.
- Treat `cumac_scheduler` specifically as a roadmap-only scheduler host until
  an external worker contract, failure-domain evidence, and cutover/rollback
  proof exist without hidden ownership handoffs.
- Treat broader profile expansion specifically as roadmap-only until each new
  RU/core/profile family is declared separately; do not promote the current
  single-`n79` lane into multi-cell, multi-DU, or broad profile parity claims.

## Cross References

- [12-target-host-deployment](./12-target-host-deployment.md)
- [14-debug-and-evidence-workflow](./14-debug-and-evidence-workflow.md)
- repo overview: `README.md`
- replacement-track posture: `subprojects/ran_replacement/README.md`
- replacement-track contracts: `subprojects/ran_replacement/contracts/README.md`
