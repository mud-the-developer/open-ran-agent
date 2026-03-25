# User Plane Edge Contract

Status: draft, docs/contracts-first

## Goal

Freeze the first implementation-facing contract for the `F1-U` and `GTP-U` user-plane boundary without adding runtime code.

This package owns the declared user-plane edge of the milestone-1 replacement lane:

- `F1-U` bearer and forwarding state between `CU-UP` and `DU`
- `GTP-U` tunnel binding and `TEID` association for the declared UE session
- the replacement-side ping-path evidence needed for attach-plus-ping acceptance
- rollback visibility when a cutover leaves stale, half-open, or misdirected forwarding state

It does not own scheduler timing, RU/fronthaul loops, or the real core's subscriber state.

## Runtime Owner

Primary runtime owner for milestone 1: `ran_cu_up`.

Supporting runtime owners:

- `ran_du_high` for DU-local forwarding orchestration and user-plane readiness surfaced to operators
- native contract gateways for timing-sensitive forwarding, drain, and resume behavior beneath the package boundary
- the real `Open5GS` core remains the external owner of core-side bearer/session state

This package remains docs/contracts-first until those ownership boundaries are frozen in contract fields and evidence.

## Cutover Owner

`ran_action_gateway` via `bin/ranctl` owns user-plane cutover planning, apply, and verify sequencing.

The cutover contract for this package requires:

- explicit target-host and control-plane readiness gates
- deterministic tunnel and forwarding state from `ran_cu_up`
- explicit DU-local readiness from `ran_du_high`
- a named rollback target whenever a new forwarding path is allowed to become active

## Rollback Owner

`ran_action_gateway` via `bin/ranctl` owns rollback orchestration.

The rollback-visible state remains owned by the participating runtimes:

- `ran_cu_up` exposes tunnel, `TEID`, and UE-session cleanup state
- `ran_du_high` exposes DU-local forwarding cleanup state
- the active native gateway exposes the drain or resume state needed to restore the last safe path

Rollback must either restore the declared prior path or prove that the replacement-side cutover state was removed cleanly.

## Boundary Inputs

Required inputs for this package come from the existing replacement-track contracts:

- replacement request contract:
  - `scope = ue_session` for attach-plus-ping verification
  - `scope = replacement_cutover` for compare, cutover, and rollback lanes
  - `required_interfaces` contains `f1_u` and `gtp_u`
- target-profile contract:
  - fixed `n79_single_ru_single_ue_lab_v1` assumptions
- core-link profile:
  - named N3 route, session, and tunnel assumptions for the declared core path
- cutover evidence:
  - compare reports, verify summaries, and rollback target naming

## Boundary Outputs

The package must eventually emit enough evidence for operators and agents to answer:

- did the replacement-side user-plane path become active
- which tunnel and forwarding state belongs to the declared UE session
- did ping traverse the declared path
- is rollback required because forwarding diverged or stayed half-open

Expected evidence fields:

- `interface_status.f1_u`
- `interface_status.gtp_u`
- `plane_status.u_plane`
- `session_status`
- `checks[]` for tunnel, forwarding, and rollback-target state
- compare and rollback evidence references for failed cutover or stale session cleanup

## Contract Rules

- Keep this package docs/contracts-first until the user-plane subset is explicit enough to implement thin adapters.
- Keep every package-local fixture schema-backed by the replacement request/status schemas.
- Treat stale `TEID` state, half-open forwarding, and ping-path divergence as first-class incidents.
- Never hide user-plane rollback needs behind a healthy control-plane or dashboard summary.

## Non-Goals

- No slot-paced logic.
- No FAPI hot-path logic.
- No PHY, RU timing, or fronthaul implementation code.
- No full `GTP-U` feature parity claim outside the declared milestone-1 subset.
- No direct Open5GS implementation code or core replacement logic in this package.

## TODO For The First Implementation Pass

- Add a package-local note for session-to-tunnel identity ownership.
- Add a package-local note for forwarding cleanup semantics during rollback.
- Add compare fixtures for `ping healthy` versus `forwarding diverged`.
- Keep the future runtime adapter thin and contract-driven.
