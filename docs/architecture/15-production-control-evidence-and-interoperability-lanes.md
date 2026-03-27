# Production Control, Evidence, And Interoperability Lanes

## Goal

Make the current production-facing control, deploy, evidence, and recovery
posture explicit without overstating runtime support beyond the lanes that
already have repo-visible proof.

This document is the current posture layer. It ties together the repo's
existing control/evidence surfaces and names which runtime lanes are
evidence-backed today versus which still need more proof before support claims
can expand further.

## Hardened Now

The repo already has a production-facing operator loop for mutation control and
evidence review. The current hardened claim is about the control and evidence
surface, plus a narrow set of runtime lanes that now have explicit proof.

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
- `artifacts/prechecks/*`, `artifacts/changes/*`, `artifacts/verify/*`, `artifacts/captures/*`, and
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

These are hardened as contract and evidence surfaces. They complement the
runtime proof for the declared live lane, but they do not by themselves claim
vendor-backed `Aerial` support, external-worker `cuMAC` support, or broad
profile parity.

## Current Support Categories

| Category | Current claim | Evidence reviewers can expect now |
| --- | --- | --- |
| Production-facing control | Hardened now | `ranctl` lifecycle, approval rules, rollback intent, control-state checks |
| Deploy and recovery operations | Hardened now | target-host preview, remote execution, fetchback, debug summaries, debug packs |
| Replacement-track evidence contracts | Hardened now | schema-backed status, compare-report, rollback-evidence, target-profile fixtures |
| Live replacement runtime cutover | Live-lab validated declared lane | real target-host lifecycle, attach-plus-ping proof, compare reports, and rollback evidence for `n79_single_ru_single_ue_lab_v1` |
| Aerial backend runtime | Bounded clean-room runtime support | shared Port gateway lifecycle, host/device probes, and restart/drain proof for `aerial_clean_room_runtime_v1` |
| cuMAC scheduler integration | Bounded clean-room scheduler support | executable slot plans, explicit CPU rollback target metadata, and cell-group failure-domain proof for `cumac_scheduler_clean_room_runtime_v1` |
| Broader interoperability profiles | Future lane | current contracts stay fixed to the declared `n79` plus real `Open5GS` scope; no multi-cell, multi-DU, or broad profile parity claim yet |

## Evidence-backed Runtime Lanes

These lanes are current support claims. They remain narrow, explicit, and tied
to reviewable proof.

| Lane | Declared target profile | Verify evidence | Rollback evidence | Health / failure-domain refs | Explicit non-claims |
| --- | --- | --- | --- | --- | --- |
| `Declared live protocol lane` | `n79_single_ru_single_ue_lab_v1` | `subprojects/ran_replacement/examples/status/verify-attach-ping-open5gs-n79.status.json`, `apps/ran_action_gateway/test/ran_action_gateway/replacement_examples_test.exs` | `subprojects/ran_replacement/examples/status/rollback-gnb-cutover-open5gs-n79.status.json`, `subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/rollback-evidence-failed-cutover-open5gs-n79.json` | `docs/architecture/03-failure-domains.md`, `docs/architecture/14-debug-and-evidence-workflow.md` | no multi-cell, multi-DU, or broad RU/core/profile parity claim |
| `Aerial` backend | `aerial_clean_room_runtime_v1` | `apps/ran_fapi_core/test/ran_fapi_core/native_gateway_contract_test.exs`, `apps/ran_fapi_core/test/ran_fapi_core/native_gateway_transport_state_test.exs` | `apps/ran_fapi_core/test/ran_fapi_core/native_gateway_contract_test.exs`, `apps/ran_fapi_core/test/ran_fapi_core/native_gateway_transport_state_test.exs` | `docs/architecture/03-failure-domains.md`, `docs/architecture/04-du-high-southbound-contract.md`, `native/aerial_adapter/CONTRACT.md` | no vendor device bring-up proof, no attach-plus-ping proof on Aerial, no production timing claim |
| `cuMAC` scheduler | `cumac_scheduler_clean_room_runtime_v1` | `apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs`, `apps/ran_du_high/test/ran_du_high_test.exs` | `apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs`, `apps/ran_du_high/test/ran_du_high_test.exs` | `docs/architecture/02-otp-apps-and-supervision.md`, `docs/architecture/03-failure-domains.md`, `apps/ran_scheduler_host/lib/ran_scheduler_host/cumac_scheduler.ex` | no external scheduler worker proof, no attach validation claim, no production timing claim |

## Future Expansion Lanes

These lanes remain explicit future work.

| Lane | Current repo posture | What must be proven before support claims expand |
| --- | --- | --- |
| Vendor-backed `Aerial` integration | Clean-room runtime support is bounded to `aerial_clean_room_runtime_v1` | vendor device bring-up, target-host attach-plus-ping on Aerial, and production timing proof |
| External-worker `cuMAC` integration | Clean-room scheduler support is bounded to `cumac_scheduler_clean_room_runtime_v1` | external worker contract, runtime timing proof, and rollback coverage that keeps scheduler ownership bounded |
| Broader RU/core/profile support | Current replacement contracts stay fixed to one `n79` / one real RU / one real UE / one real `Open5GS` core | a declared target-profile contract/example, explicit core-link contract/example, a schema-backed family bundle with a support-matrix delta and evidence bundle, plus attach-plus-ping and rollback evidence for that exact lane |
| Multi-cell or multi-DU orchestration | Mentioned in roadmap only | action scope, blast-radius rules, approval model, and evidence/rollback semantics for each additional scope before any multi-cell or multi-DU parity claim is allowed |

## Reviewer Rules

- Treat the current hardened claim as an operator-surface claim: control,
  deploy, evidence, and recovery are explicit and reviewable now.
- Treat replacement-track schemas and fixtures as evidence-model hardening that
  complements, but does not replace, runtime proof.
- Treat the declared `n79` live lane, `aerial_clean_room_runtime_v1`, and
  `cumac_scheduler_clean_room_runtime_v1` as the current bounded support lanes.
- Treat vendor-backed `Aerial`, external-worker `cuMAC`, and broader profile
  expansion as future work until each new RU/core/profile family has its own
  declared target-profile contract/example, repo-visible validation,
  support-matrix delta, deterministic rollback evidence, and schema-backed
  family bundle.
- Do not promote the current single-`n79` lane into multi-cell, multi-DU, or
  broad profile parity claims.

## Cross References

- [12-target-host-deployment](./12-target-host-deployment.md)
- [14-debug-and-evidence-workflow](./14-debug-and-evidence-workflow.md)
- repo overview: `README.md`
- replacement-track posture: `subprojects/ran_replacement/README.md`
- replacement-track contracts: `subprojects/ran_replacement/contracts/README.md`
