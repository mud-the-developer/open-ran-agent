# Core Link Edge Contract

Status: draft, docs/contracts-first

## Goal

Freeze the first implementation-facing contract for the real-core interop boundary without adding runtime code.

This package owns the declared core-link edge of the milestone-1 replacement lane:

- the named real-core profile and endpoint assumptions for `N2` and `N3`
- replacement-side visibility for `NGAP` core attachment and session handoff
- core-link divergence markers when registration or session setup stalls, rejects, or mismatches the plan
- rollback visibility when the replacement-side view of the real-core path is no longer trusted

It does not own the internal implementation of the real `Open5GS` core, radio timing, or hot-path forwarding internals.

## Runtime Owner

Primary runtime owners for milestone 1: `ran_cu_cp` and `ran_cu_up`.

Supporting ownership boundaries:

- `ran_cu_cp` owns the replacement-side `N2` and `NGAP` control state toward the real core
- `ran_cu_up` owns the replacement-side `N3` and session-tunnel state that the real core path depends on
- the real `Open5GS` core remains the external owner of subscriber, AMF/SMF/UPF, and core session state
- `ran_action_gateway` and `bin/ranctl` remain the only mutation-capable control surface for cutover and rollback

This package remains docs/contracts-first until those ownership boundaries are explicit in contract fields and evidence.

## Cutover Owner

`ran_action_gateway` via `bin/ranctl` owns core-link cutover planning, apply, and verify sequencing.

The cutover contract for this package requires:

- a named real-core profile and endpoint in plan and verify output
- explicit `NGAP`, session, and user-plane gate state from `ran_cu_cp` and `ran_cu_up`
- a named rollback target whenever a replacement-side core-link transition may change live traffic behavior

## Rollback Owner

`ran_action_gateway` via `bin/ranctl` owns rollback orchestration.

The rollback-visible state remains owned by the participating runtimes:

- `ran_cu_cp` exposes the last trusted replacement-side `NGAP` and registration state
- `ran_cu_up` exposes the replacement-side session and tunnel cleanup state
- the workpad, compare report, and rollback evidence must preserve whether the failure was caused by the replacement lane or by the real core

Rollback must never hide external-core rejection behind an ambiguous replacement-side status.

## Boundary Inputs

Required inputs for this package come from existing replacement-track contracts:

- replacement request contract:
  - `scope = ue_session` for attach-plus-ping verification
  - `scope = replacement_cutover` for compare, cutover, and rollback lanes
- target-profile contract:
  - fixed `n79_single_ru_single_ue_lab_v1` assumptions
- core-link profile:
  - real-core endpoint, subscriber assumptions, and session-route narrowing
- attach and session evidence:
  - NGAP traces, session setup traces, and rollback-target naming

## Boundary Outputs

The package must eventually emit enough evidence for operators and agents to answer:

- which real-core endpoint the lane targeted
- whether replacement-side core attachment progressed far enough for registration
- whether session establishment and the declared user-plane path stayed aligned with the plan
- whether rollback is required because the core-link path is no longer trustworthy

Expected evidence fields:

- `core_endpoint`
- `core_link_status`
- `interface_status.ngap`
- `ngap_procedure_trace`
- `interface_status.gtp_u`
- `attach_status`
- `session_status`
- `checks[]` for endpoint identity, session handoff, and rollback-target state

## Contract Rules

- Keep this package docs/contracts-first until the real-core interop subset is explicit enough to implement thin adapters.
- Keep every package-local fixture schema-backed by the replacement request/status schemas.
- Treat core rejection, session handoff mismatch, and route divergence as first-class incidents.
- Never imply replacement-side success without naming the real-core endpoint and the active rollback target.

## Non-Goals

- No slot-paced logic.
- No FAPI hot-path logic.
- No internal Open5GS implementation code or core replacement logic in this package.
- No hidden lab-only shortcuts that bypass the declared core-link profile.
- No claim of broad `NGAP` or `GTP-U` parity outside the declared milestone-1 subset.

## TODO For The First Implementation Pass

- Add a package-local note for real-core endpoint identity and profile ownership.
- Add a package-local note for replacement-side versus core-side failure attribution.
- Add compare fixtures for `registration healthy` versus `core rejected session`.
- Keep the future runtime adapter thin and contract-driven.
