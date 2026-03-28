# NGAP And Registration Standards Subset

Status: draft

## Goal

Define the minimum NGAP-facing behavior that the replacement track must own for milestone 1 on the `n79` target profile.

The target is not "NGAP looks alive". The target is:

- a real UE attaches through the replacement lane
- the replacement lane reaches a real `Open5GS` core
- registration evidence is explicit
- the behavior stays standards-correct for the declared subset

## Conformance Frame

This subset is judged against:

- `3GPP TS 38.413` for the declared `NGAP` behavior
- `subprojects/ran_replacement/notes/09-ngap-procedure-support-matrix.md` for
  required, supported, and deferred procedure classes
- `subprojects/ran_replacement/notes/16-oai-visible-5g-standards-conformance-baseline.md`
  for the repo-wide conformance and evidence mapping

## Why A Subset Is Needed

The replacement track is intentionally narrow.
Trying to describe full NGAP parity up front would hide scope and delay implementation.

This subset exists to make three things explicit:

- which procedures must work for milestone 1
- which ordering assumptions must hold
- which deviations are temporary and visible

The subset is a baseline for `n79`, not a claim of full 5G attach coverage.

## Required Procedures

Milestone 1 must support the procedures needed for registration on the declared profile:

- `NG Setup`
- `Initial UE Message`
- `Downlink NAS Transport`
- `Uplink NAS Transport`
- `UE Context Release` when attach or rollback requires cleanup

The supported subset must be sufficient for:

- cell access
- registration
- session establishment handoff into the core
- release handling after failure or rollback

Milestone 1 also claims bounded support for:

- `Error Indication`
- `Reset`

These are reviewable recovery or diagnosis claims, not happy-path pass gates.
They must remain explicit in compare-report, status, and rollback evidence.

## Procedure Ordering Assumptions

The replacement lane should treat the following as the expected ordering model for milestone 1:

1. target-host preflight
2. RU sync and radio readiness
3. NG setup to the core
4. UE access and initial registration signaling
5. NAS transport exchange
6. core-side registration acceptance
7. session establishment handoff
8. ping evidence
9. cleanup or rollback if needed

The implementation may retry or back off internally, but it must not hide ordering failure in the evidence surface.

## Evidence Expectations

Every successful or failed run must expose enough evidence to answer:

- did NG setup succeed
- did UE registration progress past initial access
- which NGAP procedure was last observed
- what core endpoint was contacted
- whether the failure belongs to timing, access, control signaling, or core rejection

The status surface should keep these artifacts visible:

- `precheck`
- `plan`
- `verify`
- `capture-artifacts`
- rollback evidence when registration fails or is aborted

## Allowed Temporary Deviations

Temporary deviations are allowed only when they are explicit and bounded.

For milestone 1, acceptable deviations include:

- a narrow procedure subset rather than full NGAP parity
- one declared target profile rather than general `n79` support
- explicit fallback to the current OAI reference path while the replacement lane is still shadowing
- read-only comparison or probe helpers that do not mutate runtime

These deviations are acceptable only if they are:

- documented before implementation
- surfaced in `precheck`, `plan`, `verify`, or incident artifacts
- paired with an explicit rollback target

## Negative Space

This subset does not claim:

- full NGAP procedure parity
- multi-cell support
- handover
- mobility management beyond the declared target profile
- standards coverage outside the milestone 1 registration path
- core ownership beyond the declared external `Open5GS` interop boundary
