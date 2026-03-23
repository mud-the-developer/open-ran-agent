# Open Questions And Risks

## Assumptions

- SA-only is sufficient for the first implementation wave.
- A Port sidecar can satisfy early southbound integration needs without unacceptable overhead.
- One canonical IR can represent both local and Aerial backend needs at the DU-high boundary.

## Open Questions

1. Which protocol-heavy modules, if any, should move from Elixir to Erlang once runtime work starts?
2. What binary framing should be used on the Port boundary?
3. How much scheduler state must remain replayable for safe rollback?
4. How should approval evidence be stored and surfaced to `ranctl`?
5. What is the minimal artifact bundle required for backend switch incidents?

## Risks

- A too-generic canonical IR may hide backend-specific requirements until late.
- A too-specific canonical IR may leak vendor constraints into core apps.
- Port IPC overhead may become unacceptable on some southbound paths.
- Operational sprawl may appear if skills bypass `ranctl`.
- Missing config validation could widen blast radius beyond a single cell group.

## Mitigations

- keep IR versioned and capability-driven
- prototype the Port boundary with a stub profile early
- enforce `ranctl` as the only mutable entrypoint
- keep verification windows explicit and bounded
- add integration tests for rollback before enabling live backend switching

## Deferred Decisions

- exact release topology
- exact artifact retention policy
- exact approval system integration
- distributed versus single-node runtime topology
