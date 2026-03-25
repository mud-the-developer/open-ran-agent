# ADR 0008: OAI CU/DU Function And Standards Baseline

## Status

Accepted

## Context

The `subprojects/ran_replacement/` track is not meant to become a thin operator wrapper around another runtime.

Without an explicit baseline, "OAI CU/DU replacement" can degrade into something much weaker:

- a lifecycle wrapper that still depends on OAI for the real function
- a protocol adapter that does not truly own the target behavior
- a lab demo that works only because standards-sensitive behavior is deferred
- a parity claim that is really only configuration or orchestration parity

The repository needs a stronger statement of intent:

- the replacement track must implement the relevant `CU/DU` functions for the declared target profile
- the external protocol behavior must be standards-correct for the declared scope
- the target is still narrow and milestone-bound, not a blanket claim of universal parity

## Decision

Use the operator-visible `OAI NR CU/DU` function set for the declared target profile as the replacement baseline, and require standards-correct behavior at the declared external interfaces.

For milestone 1 this means:

- the replacement track must own the `CU-CP`, `CU-UP`, and `DU` responsibilities needed to complete the declared `n79` target-profile path
- the declared target-profile function chain includes:
  - cell bring-up
  - RU readiness and sync gate
  - UE access path sufficient for `RACH`, `RRC setup`, registration, PDU session establishment, and ping
  - control and user-plane progression required for the declared end-to-end path
- the declared external interfaces must be standards-correct for the supported profile:
  - `NGAP`
  - `F1-C`
  - `F1-U`
  - `E1AP`
  - `GTP-U`
- internal implementation does not need to resemble OAI source layout
- internal BEAM versus native ownership remains a separate decision from functional parity

## Allowed Temporary Deviations

Temporary deviations are allowed only when all of the following hold:

- they are limited to `shadow` or explicitly `experimental` profile states
- they are declared before implementation in docs, ADRs, or task notes
- they are surfaced in `precheck`, `plan`, `verify`, or incident artifacts
- they preserve an explicit rollback target
- they do not claim standards parity for unsupported interfaces or unsupported procedure classes

For milestone 1, allowed temporary deviations include:

- narrow target-profile support instead of broad feature parity
- additive management adapters for observability and deploy flow
- staged ownership where some families remain `shadow` before `cutover`
- external infrastructure ownership for timing, sync, or host capabilities that the replacement stack does not itself implement

## Consequences

Positive:

- "replacement" now means real functional ownership, not orchestration-only ownership
- standards claims become reviewable against named interfaces
- attach-plus-ping success is tied to explicit function ownership
- task planning can separate true parity work from operator tooling work

Negative:

- implementation scope is stricter than a lifecycle-wrapper project
- standards-sensitive verification work must begin earlier
- narrow milestone language becomes more important to avoid overclaiming

## Alternatives Considered

- Treat OAI only as an operational reference and not a functional baseline: rejected because replacement would remain ambiguous.
- Treat only attach success as the goal without explicit standards language: rejected because success could hide protocol shortcuts or non-portable behavior.
- Require full broad parity before any milestone claim: rejected because the repository needs a narrow, real-lab first proof target.

