# ADR 0006: Open5GS Public Surface Compatibility Baseline

## Status

Accepted

## Context

The `subprojects/elixir_core/` track exists to replace Open5GS-style core functions with Elixir OTP applications, but internal Elixir app boundaries will not match upstream process or source layouts exactly.

Without a fixed compatibility baseline, "Open5GS replacement" becomes ambiguous:

- parity claims can drift into partial feature coverage
- management and observability surfaces can be deferred until too late
- operator workflows can break even when protocol paths appear healthy
- config and cutover work can leak private or ad hoc interfaces into the public contract

## Decision

Use the Open5GS public 5GC surface as the compatibility baseline for the Elixir-core track.

This means:

- preserve the published 5GC NF set as the baseline surface:
  - `NRF`
  - `SCP`
  - `SEPP`
  - `AMF`
  - `SMF`
  - `UPF`
  - `AUSF`
  - `UDM`
  - `UDR`
  - `PCF`
  - `NSSF`
  - `BSF`
- treat standards-aligned external I/O as first-class contracts:
  - `SBI`
  - `NGAP`
  - `PFCP`
  - `GTP-U`
- treat operator-facing management I/O as part of parity, not optional tooling:
  - metrics
  - info API
  - subscriber admin and WebUI expectations
  - config import and render paths
- keep compatibility state additive inside `RanConfig` through a `core_topology` model rather than replacing the current RAN bootstrap shape
- require `ranctl` artifacts to surface compatibility profile, required NF set, required I/O surfaces, and declared deviations

## Allowed Temporary Deviations

Temporary deviations are allowed only when all of the following hold:

- they are limited to `shadow` or explicitly `experimental` profiles
- they are declared in docs or ADRs before implementation
- they are surfaced in `precheck`, `plan`, `verify`, or rollout evidence
- they preserve a deterministic rollback target

For the first milestone, these temporary deviations are explicitly allowed:

- shadow-mode Elixir ownership before direct cutover
- compatibility adapters for management I/O instead of identical internal implementations
- external UPF datapath while keeping `PFCP` and user-plane behavior standards-correct at the boundary
- no claim of EPC parity in the first 5GC milestone

## Consequences

Positive:

- parity claims become reviewable and testable
- management surfaces are designed early instead of becoming retrofit debt
- `RanConfig`, `ranctl`, and dashboard work can share one compatibility vocabulary
- cutover readiness can be evaluated against declared NF and I/O requirements

Negative:

- the compatibility target is broader than a narrow attach-only MVP
- config and validation work must start earlier
- some management-surface adapters may exist before full internal runtime implementation

## Alternatives Considered

- Treat Open5GS only as loose inspiration: rejected because parity would be unmeasurable.
- Match only N2 and N4 protocol behavior: rejected because operator-visible behavior would still drift.
- Replace the bootstrap RAN topology model with a core-only model: rejected because the repo still needs additive coexistence during transition.
