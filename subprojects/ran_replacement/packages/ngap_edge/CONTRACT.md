# NGAP Edge Contract

Status: draft, docs/contracts-first

## Goal

Freeze the first implementation-facing contract for the NGAP boundary without placing runtime logic in the package.

This package owns the declared `NGAP` edge of the milestone-1 replacement lane:

- node-level `NG Setup` toward the real `Open5GS` core
- UE attach entry into the NG control plane
- NAS transport exchange needed for registration
- cleanup visibility through `UE Context Release`

It does not own RU timing, scheduler decisions, or user-plane forwarding.

## Runtime Owner

Primary runtime owner for milestone 1: `ran_cu_cp`.

Supporting ownership boundaries:

- `ran_cu_cp` owns the replacement-side NGAP session and attach-control state that this package will eventually surface.
- the real `Open5GS` core remains the external owner of subscriber, registration, and session state beyond the NGAP peer boundary
- `ran_action_gateway` and `bin/ranctl` remain the only mutation-capable control surface for any cutover or rollback that depends on this package

No package-layer runtime code lands here until the contract, schema references, and evidence fields are explicit.

## Cutover Owner

`ran_action_gateway` via `bin/ranctl` owns NGAP-facing cutover planning, apply, and verify sequencing.

The cutover lane may only trust this package when:

- the target host and control-plane gates are explicit
- the named core endpoint is present in plan and verify output
- `ran_cu_cp` can surface the last observed NGAP procedure and the active rollback target

## Rollback Owner

`ran_action_gateway` via `bin/ranctl` owns rollback orchestration for this package.

`ran_cu_cp` owns the rollback-visible replacement-side state:

- the last observed NGAP procedure
- `UE Context Release` cleanup state
- evidence that control returned to the last safe pre-attach or pre-cutover target

## Boundary Inputs

The package reads from existing replacement-track contracts rather than inventing a parallel control surface.

Required inputs:

- replacement request contract:
  - `scope = ue_session`
  - `metadata.replacement.required_interfaces` contains `ngap`
- target-profile contract:
  - `n79_single_ru_single_ue_lab_v1`
- lab-owner overlay:
  - real host, RU, UE, and Open5GS narrowing for the declared lab
- core-link profile:
  - N2 endpoint, subscriber profile, and session assumptions

## Boundary Outputs

The package must eventually emit enough state for `ranctl`, dashboard, and evidence capture to answer:

- did `NG Setup` complete
- what was the last observed NGAP procedure
- did registration advance past initial access
- did the core reject the subscriber or stall the exchange
- did release cleanup complete after failure or rollback

Expected evidence fields:

- `interface_status.ngap`
- `core_link_status`
- `attach_status`
- `checks[]` for the last known NGAP checkpoint
- artifact references for NGAP trace, attach trace, and cleanup trace

## Contract Rules

- Keep all mutating actions routed through `bin/ranctl`.
- Keep package fixtures schema-backed by the existing replacement request/status schemas.
- Treat `registration rejected`, `NG setup failed`, and `release cleanup incomplete` as first-class package incidents.
- Keep the rollback target explicit whenever NGAP-facing attach progress is not trusted.

## Non-Goals

- No slot-paced logic.
- No FAPI hot-path logic.
- No PHY, RU timing, or fronthaul state machine here.
- No direct Open5GS implementation code in this package yet.
- No claim of full NGAP parity outside the declared milestone-1 subset.

## TODO For The First Implementation Pass

- Add a package-local note for `NG Setup` state ownership.
- Add a package-local note for `UE Context Release` cleanup semantics.
- Add a package-local compare fixture for `registration accepted` versus `registration rejected`.
- Keep the future runtime adapter thin and contract-driven.
