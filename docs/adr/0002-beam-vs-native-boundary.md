# ADR 0002: BEAM Versus Native Boundary

## Status

Accepted

## Context

DU-high orchestration belongs on the BEAM, but slot-paced southbound work and backend-specific transport may require tighter latency and isolation guarantees.

## Decision

Use a native sidecar behind `fapi_rt_gateway` as the first southbound runtime boundary. Connect to it from BEAM through a Port.

BEAM owns:

- cell-group lifecycle
- scheduler orchestration
- backend selection
- change control
- observability metadata

Native sidecar owns:

- RT-adjacent transport loops
- backend-specific framing
- backend process lifecycle below the gateway contract

## Consequences

Positive:

- crashes are contained outside the VM
- implementation language stays open
- gateway replacement or restart is easier than with an in-VM NIF

Negative:

- IPC framing and copy overhead must be measured
- gateway supervision spans BEAM and OS process models

## Alternatives Considered

- NIF: lower boundary overhead, higher VM risk.
- External daemon only: workable later, but Port sidecar keeps ownership tighter for MVP.
