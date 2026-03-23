# System Overview

## Purpose

This repository defines the control, orchestration, and operations architecture for a 5G SA Open RAN stack that covers CU-CP, CU-UP, and DU-high while preserving a strict native boundary for timing-sensitive southbound work.

## MVP Goal

The first meaningful target is:

- one DU
- one cell group
- one UE
- attach plus ping
- controlled backend failover between pre-provisioned targets

## System Shape

```text
                +--------------------------------------+
                | Symphony / Codex / skill workflows   |
                | decision support only                |
                +-------------------+------------------+
                                    |
                                    v
                           +--------+--------+
                           |    bin/ranctl   |
                           | deterministic   |
                           +--------+--------+
                                    |
             +----------------------+----------------------+
             |                                             |
             v                                             v
   +---------+----------+                       +----------+-----------+
   | BEAM control plane |                       | observability /      |
   | CU-CP / CU-UP /    |                       | artifacts / config   |
   | DU-high / actions  |                       +----------------------+
   +---------+----------+
             |
             v
   +---------+----------+
   | ran_fapi_core      |
   | canonical IR       |
   +---------+----------+
             |
             v
   +---------+----------+
   | native fapi gateway|
   | Port sidecar       |
   +----+-----------+---+
        |           |
        v           v
 local_du_low   aerial_backend
```

## Major Boundaries

- BEAM core: topology, state machines, failure handling, orchestration, config, observability.
- Native gateway: slot-paced and backend-specific RT-adjacent transport.
- Backend adapters: `local_du_low`, `aerial_backend`, and `stub_fapi_profile`.
- Ops plane: `ranctl`, skills, and Symphony/Codex workflows.

## Architecture Choices

- Use Mix umbrella so multiple OTP applications share one repository and one release discipline.
- Standardize southbound traffic on a canonical IR to prevent backend-specific leakage into DU-high logic.
- Keep scheduler logic behind a host boundary so CPU and future cuMAC schedulers are swappable.
- Use `precheck -> plan -> apply -> verify -> rollback` for all mutating operations.

## Assumptions

- RU-side low-PHY remains external to BEAM-managed code.
- FAPI-like semantics are sufficient for DU-high to native gateway exchange.
- Backend switching is limited to pre-provisioned targets, not ad hoc shell-level failover.

## Deferred Decisions

- exact ASN.1 and NGAP/F1AP/E1AP codec strategy
- exact transport libraries for SCTP and GTP-U
- real DU-low and Aerial runtime implementations
