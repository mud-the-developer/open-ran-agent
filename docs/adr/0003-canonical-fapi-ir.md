# ADR 0003: Canonical FAPI IR

## Status

Accepted

## Context

The DU-high layer must support at least a local DU-low backend and a future Aerial backend without leaking backend-specific details into core orchestration logic.

## Decision

Represent southbound intent as a versioned canonical IR centered on a `slot_batch`.

The IR includes:

- `ir_version`
- `cell_group_id`
- `ue_ref`
- `frame`
- `slot`
- `profile`
- ordered `messages`
- `metadata`

Backends negotiate capabilities against the IR rather than redefining the DU-high boundary.

## Consequences

Positive:

- one contract for local, stub, and future Aerial profiles
- validation and artifact capture can be standardized
- scheduler outputs remain backend-agnostic

Negative:

- IR design must stay disciplined or it will drift into lowest-common-denominator ambiguity
- some backend-specific features may require extension fields or capability flags

## Alternatives Considered

- Backend-specific request objects: simpler short term, but leaks backend details into DU-high.
- Message-by-message pass-through: weaker for batching, rollback planning, and verification.
