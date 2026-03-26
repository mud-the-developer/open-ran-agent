# Target Host Edge Contract

Status: draft, docs/contracts-first

## Goal

Freeze the host-readiness boundary for the replacement track before any runtime code lands here.

This package owns the declared preflight edge for the milestone-1 lane:

- host inventory and deployment layout checks
- hugepage and kernel expectation checks
- sync and fronthaul resource gating
- explicit blocking or readiness evidence before attach or cutover

It does not own NGAP, F1, E1, GTP-U, or live packet handling.

## Runtime Owner

Primary repo-visible runtime owners for milestone 1: `ran_config` and `ran_action_gateway`.

Supporting ownership boundaries:

- `ran_config` owns topology, profile, and inventory interpretation for this package
- `ran_action_gateway` and `bin/ranctl` own precheck, plan, verify, and operator-visible gate state
- the external target host remains the live owner of NIC, kernel, timing, hugepage, and install state that this package only observes

This package remains read-mostly until those host-readiness fields are frozen in contract and evidence form.

## Cutover Owner

`ran_action_gateway` via `bin/ranctl` owns the cutover gate for this package.

The package may only report a host as cutover-capable when:

- the declared target profile and deploy/profile state are explicit
- the readiness checks surface a named rollback target
- the host evidence bundle explains why the lane is `ready_for_preflight` or `ready_for_apply`

## Rollback Owner

`ran_action_gateway` via `bin/ranctl` owns rollback orchestration for host-readiness regressions.

For this package, rollback means:

- returning the operator-visible lane to the last approved deploy/profile state
- preserving the evidence that explains why the newer host-readiness state was rejected
- never implying that a host-side fallback happened without a named artifact path

## Boundary Inputs

Required inputs for this package come from existing replacement-track contracts:

- replacement request contract:
  - `scope = target_host`
  - `metadata.replacement.action = precheck`
  - `metadata.replacement.native_probe` present
- target-profile contract:
  - fixed `n79_single_ru_single_ue_lab_v1` assumptions
- lab-owner overlay:
  - concrete host, RU, and deployment narrowing
- core-link profile:
  - used only to confirm the declared N2/N3 reachability assumptions

## Boundary Outputs

The package must eventually emit enough evidence for operators and agents to answer:

- which host dependency is missing or degraded
- whether timing and fronthaul prerequisites are ready
- whether the declared rollback target is still known
- whether the host is ready for preflight only, or ready for live apply

Expected evidence fields:

- `checks[]` for host, RU sync, and core reachability
- `plane_status.s_plane`, `plane_status.m_plane`, `plane_status.c_plane`, `plane_status.u_plane`
- `ru_status`
- `core_link_status`
- artifact references for host inventory, timing state, RU readiness, and user-plane readiness

## Operator Workflow Rules

The package must keep the go/no-go workflow explicit for operator review.

Repo-visible evidence should always make it possible to identify:

- the first blocked or degraded readiness layer
- the named rollback target
- the next artifact to inspect
- whether the lane is `ready_for_preflight` or `ready_for_apply`

## Contract Rules

- Keep this package read-mostly until the explicit preflight contract is stable.
- Keep every package-local fixture schema-backed by the replacement request/status schemas.
- Treat `blocked` as the default when the declared lab requirements are not yet proven.
- Never allow this package to imply live readiness without explicit evidence references.

## Non-Goals

- No slot-paced logic.
- No FAPI hot-path logic.
- No PHY or RU timing implementation code.
- No core protocol implementation code.
- No hidden host-specific secrets or private inventory inside committed fixtures.

## TODO For The First Implementation Pass

- Add a package-local note for readiness score derivation and gating thresholds.
- Add a package-local note for inventory redaction and operator-visible host naming.
- Add compare fixtures for `blocked` versus `ready_for_preflight`.
- Keep the future host probe adapter thin and contract-driven.
