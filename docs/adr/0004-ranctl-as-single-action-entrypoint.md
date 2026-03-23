# ADR 0004: ranctl As Single Action Entrypoint

## Status

Accepted

## Context

Operations need automation, but allowing every workflow or skill to mutate the system directly would fragment auditability, approval handling, and rollback semantics.

## Decision

All mutating operational changes must pass through `bin/ranctl`.

`ranctl` owns:

- request validation
- prechecks
- plan generation
- apply execution
- verify flow
- rollback flow
- artifact capture hooks

Skills and higher-level automation may call `ranctl`, but must not bypass it for supported actions.

## Consequences

Positive:

- one audited action surface
- one place to enforce approval gates
- consistent rollback and artifact capture semantics

Negative:

- early `ranctl` design must be broad enough to avoid frequent bypass pressure
- some experimental workflows may feel slower until the CLI surface grows

## Alternatives Considered

- Direct shell automation from skills: fast to start, poor control and auditability.
- App-specific mutation APIs: too fragmented for ops discipline.
