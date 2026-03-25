# F1E1 Control Edge Contract

Status: draft, docs/contracts-first

## Goal

Freeze the first implementation-facing control-plane contract for the `F1-C` and `E1AP` boundary without adding runtime code.

This package owns the declared control-plane coordination edge for milestone 1:

- CU-CP to DU association and setup state
- CU-CP to CU-UP association and setup state
- configuration exchange needed for the `n79_single_ru_single_ue_lab_v1` profile
- UE context lifecycle and release visibility
- control-plane divergence markers during cutover or rollback

It does not own NGAP-facing core registration, user-plane forwarding, or RT scheduler behavior.

## Boundary Inputs

Required inputs for this package come from the existing replacement-track contracts:

- replacement request contract:
  - `scope = replacement_cutover` for cutover observation and rollback lanes
  - `required_interfaces` contains `f1_c` and `e1ap`
- target-profile contract:
  - fixed `n79_single_ru_single_ue_lab_v1` configuration assumptions
- lab-owner overlay:
  - concrete DU/CU placement, host narrowing, and inventory references
- cutover evidence:
  - compare reports, rollback target, and operator-facing state transitions

## Boundary Outputs

The package must eventually emit enough evidence for operators and agents to answer:

- did the `F1-C` association succeed and stay aligned with the plan
- did the `E1AP` association succeed and stay aligned with the plan
- did control-plane divergence occur during cutover
- is rollback required to restore a clean control-plane state

Expected evidence fields:

- `interface_status.f1_c`
- `interface_status.e1ap`
- `plane_status.c_plane`
- `checks[]` for association, rollback target, and divergence explanation
- rollback evidence references for failed cutover or partial setup

## Contract Rules

- Keep this package docs/contracts-first until the control-plane subset is explicit enough to implement thin adapters.
- Keep every package-local fixture schema-backed by the replacement request/status schemas.
- Treat partial setup, stale association, and incomplete release as first-class incidents.
- Never hide control-plane divergence behind a successful user-plane or dashboard surface.

## Non-Goals

- No slot-paced logic.
- No FAPI hot-path logic.
- No PHY, RU timing, or fronthaul implementation code.
- No direct Open5GS implementation code here.
- No claim of full `F1-C` or `E1AP` parity outside the declared milestone-1 subset.

## TODO For The First Implementation Pass

- Add a package-local note for association identity and peer-state ownership.
- Add a package-local note for `UE Context Release` and control-plane cleanup semantics.
- Add a compare fixture for `setup healthy` versus `cutover diverged`.
- Keep the future runtime adapter thin and contract-driven.
