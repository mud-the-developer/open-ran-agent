# F1-C And E1AP Standards Subset

Status: draft

## Goal

Define the minimum standards-correct control-plane behavior that the replacement track must own for milestone 1 on the `n79_single_ru_single_ue_lab_v1` profile.

This note is intentionally narrow:

- one real RU
- one real UE
- one real `Open5GS` core
- one gNB path
- one attach-plus-ping proof path

The purpose is not to claim broad `F1-C` or `E1AP` parity. The purpose is to make the required control-plane subset explicit before implementation expands.

## Conformance Frame

This subset is judged against:

- `3GPP TS 38.473` for the declared `F1-C` behavior
- `3GPP TS 37.483` for the declared `E1AP` behavior
- `subprojects/ran_replacement/notes/10-f1-c-and-e1ap-procedure-support-matrix.md`
  for required procedures and explicit deferrals
- `subprojects/ran_replacement/notes/16-oai-visible-5g-standards-conformance-baseline.md`
  for the repo-wide conformance and evidence mapping

## Required Procedure Subset

The milestone 1 control-plane subset should cover the procedures needed to complete and hold a real-lab attach path:

- `F1-C`
  - gNB to DU association and setup
  - DU to CU configuration exchange
  - cell and serving-cell setup needed for the declared target profile
  - UE context creation, release, and re-establishment guard state
  - single-lane UE context refresh that stays inside the declared DU and serving-cell ownership
  - bearer or DRB control progression required for registration and session setup
  - failure and release handling needed for deterministic rollback evidence
- `E1AP`
  - CU-CP and CU-UP association and setup
  - bearer or activity-state coordination needed for the target profile
  - control-path state needed to support the declared attach and session path
  - clean bearer release and re-establishment behavior during cutover or rollback
  - single-lane bearer-context refresh that remains handover-adjacent without moving ownership across DU or CU-UP boundaries

The subset must be standards-correct for the supported procedure set. Unsupported procedures should be explicitly out of scope rather than partially faked.

The first handover-adjacent `F1-C` and `E1AP` transitions stay bounded:

- they may refresh context or bearer state inside the already-declared single-lane ownership path
- they must not imply multi-DU, multi-cell, path-switch, or source-target mobility support

## State Assumptions

The control-plane state model for milestone 1 should assume:

- a single gNB instance
- a single DU instance
- a single CU-CP/CU-UP ownership boundary
- a single active cell profile
- a real external core handling registration and session state
- explicit rollback targets for any cutover-capable state transition

The replacement lane should be able to explain the active state at each step:

- precheck
- bring-up
- association
- configuration
- registration
- session setup
- verify
- rollback

If a state transition cannot be described in the same vocabulary across BEAM, native workers, and evidence artifacts, it is not ready for milestone 1.

## Evidence Expectations

Each supported procedure subset should produce deterministic evidence:

- setup evidence for `F1-C`
- setup evidence for `E1AP`
- association state and peer identity
- protocol health markers
- release or failure markers
- rollback or re-establishment markers where relevant

The evidence must be usable by:

- `ranctl`
- the dashboard
- operator incident review
- later cutover readiness checks

At minimum, milestone 1 should expose enough evidence to answer:

1. Did the control-plane association succeed?
2. Did the declared configuration reach the target profile?
3. Did the attach path progress far enough for real registration?
4. Did the cutover or rollback leave a clean state?

## Ownership Split

The replacement track should be explicit about ownership:

- BEAM owns lifecycle planning, configuration validation, approval gating, evidence capture, and operator-facing state.
- Native workers own any timing-sensitive transport or protocol framing needed for the control-plane boundary.
- External core infrastructure owns its own subscriber, registration, and session state.

For milestone 1, `F1-C` and `E1AP` should be treated as control-plane contracts, not shell-script side effects.

## Allowed Temporary Deviations

Temporary deviations are acceptable only if they are declared before implementation and surfaced in evidence:

- shadow-mode only before direct cutover
- explicit procedure subset instead of full protocol coverage
- compatibility adapters for observability or management surfaces
- external ownership for capabilities outside the declared milestone-1 control-plane subset
- bounded fallback to the reference runtime while the replacement lane is still proving the target profile

Temporary deviations are not acceptable if they:

- hide unsupported procedures behind "works well enough"
- skip standards-correct setup or release handling
- erase rollback evidence
- blur the ownership line between the replacement lane and the real core

## Negative Space

This note does not claim:

- full `F1-C` procedure parity beyond the target-profile subset
- full `E1AP` procedure parity beyond the target-profile subset
- multi-cell control-plane scaling
- handover transfer or path switch across a new DU, CU-UP, or serving-cell ownership boundary
- cross-lab portability
- replacing the real `Open5GS` core in this track
- RT hot-path implementation details

## Boundary Rule

If the milestone 1 attach path cannot be explained in terms of standards-correct `F1-C` and `E1AP` state transitions, then the replacement track is not ready to own the control-plane function chain yet.
