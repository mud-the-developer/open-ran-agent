# OAI Function And Standards Baseline

Status: draft

## Goal

Remove ambiguity from the phrase `OAI CU/DU replacement`.

For this track, replacement must mean:

- owning the target-profile `CU/DU` function chain
- not merely wrapping another runtime
- not merely matching configuration or deployment flow
- not merely producing a lab demo with hidden shortcuts

## Functional Baseline

For milestone 1, the replacement lane must own the functions needed for one real `n79` profile:

- cell bring-up
- RU readiness gate
- sync gate
- access path sufficient for `RACH`
- control progression sufficient for `RRC setup`
- real registration path to the external core
- real PDU session establishment path
- real user-plane path sufficient for ping

This is deliberately narrower than broad parity, but stronger than "basic orchestration works."

## Standards Baseline

The declared external interfaces must behave in a standards-correct way for the supported target profile.

Named interfaces for milestone 1:

- `NGAP`
- `F1-C`
- `F1-U`
- `E1AP`
- `GTP-U`

The exact supported procedure subset still needs to be written down per interface, but the direction is explicit:

- no fake parity claims
- no hidden private shortcuts disguised as final behavior
- no attach success that depends on undefined interface behavior

## What Counts As Success

For milestone 1, success is:

- one real RU
- one real UE
- one real `Open5GS` core
- one `n79` target profile
- registration
- PDU session
- ping

with evidence that the required function chain is truly owned by the replacement lane for the declared scope.

## What Does Not Count

These do not count as replacement success by themselves:

- config rendering only
- deploy automation only
- dashboard visibility only
- `RFsim` only
- attach without a trustworthy user-plane result
- ping without clear standards-correct control progression

