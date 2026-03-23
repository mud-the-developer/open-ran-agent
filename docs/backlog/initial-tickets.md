# Initial Tickets

The tickets below are ordered for MVP-first delivery. Each item includes priority, risk, and primary dependency.

## P0

1. P0 | Implement canonical IR validation in `ran_fapi_core`. Risk: high. Depends on ADR 0003.
2. P0 | Wire `bin/ranctl` to a real BEAM executor in `ran_action_gateway`. Risk: high. Depends on ADR 0004.
3. P0 | Define the Port wire format between `ran_fapi_core` and `fapi_rt_gateway`. Risk: high. Depends on ADR 0002.
4. P0 | Add explicit backend capability negotiation and health status schemas. Risk: high. Depends on `docs/architecture/04-du-high-southbound-contract.md`.
5. P0 | Implement `stub_fapi_profile` end-to-end path for contract testing. Risk: high. Depends on tickets 1, 3, and 4.
6. P0 | Add config validation for `cell_group`, backend, and scheduler profile declarations. Risk: high. Depends on `ran_config`.
7. P0 | Define rollback plan persistence format for `change_id`. Risk: high. Depends on ADR 0004.
8. P0 | Add verification checks for gateway health, cell-group state, and UE ping. Risk: high. Depends on `docs/architecture/05-ranctl-action-model.md`.
9. P0 | Implement approval evidence handoff from workflow layer to `ranctl`. Risk: medium. Depends on ADR 0005.
10. P0 | Build initial artifact bundle structure for failed changes and incidents. Risk: medium. Depends on `ran_observability`.
11. P0 | Add integration harness for backend switch success and rollback paths. Risk: high. Depends on tickets 2, 5, 7, and 8.
12. P0 | Define `cell_group` drain semantics and admission freeze semantics. Risk: high. Depends on `docs/architecture/03-failure-domains.md`.

## P1

13. P1 | Add `cpu_scheduler` output schema that maps directly into canonical IR. Risk: medium. Depends on ADR 0003.
14. P1 | Decide which protocol-heavy modules should start in Elixir versus Erlang. Risk: medium. Depends on ADR 0001.
15. P1 | Add gateway session restart workflow inside `ran_fapi_core`. Risk: medium. Depends on ADR 0002.
16. P1 | Create release packaging strategy for umbrella apps plus native sidecars. Risk: medium. Depends on ADR 0001.
17. P1 | Add runtime topology loader for single DU / single cell lab configs. Risk: medium. Depends on `ran_config`.
18. P1 | Implement structured logging fields for `change_id`, `incident_id`, and `cell_group`. Risk: medium. Depends on `ran_observability`.
19. P1 | Add artifact capture adapters for logs, config snapshots, and gateway traces. Risk: medium. Depends on ticket 10.
20. P1 | Write executable skill wrapper scripts that only call `bin/ranctl`. Risk: low. Depends on `ops/skills/*`.
21. P1 | Define `observe` response schema and incident summary format. Risk: medium. Depends on `docs/architecture/06-symphony-codex-skills-ops.md`.
22. P1 | Add health-state transitions for `healthy`, `degraded`, `draining`, and `failed`. Risk: medium. Depends on ticket 4.
23. P1 | Design state rehydration rules for `ue_subtree` restart. Risk: medium. Depends on `docs/architecture/03-failure-domains.md`.
24. P1 | Add test fixtures for `local_fapi_profile` and `aerial_fapi_profile` capability negotiation. Risk: low. Depends on ticket 4.
25. P1 | Define backend switch metrics and SLO signals for verification. Risk: medium. Depends on ticket 8.
26. P1 | Add release-time config sanity checks that reject missing rollback targets. Risk: medium. Depends on tickets 6 and 7.

## P2

27. P2 | Prototype a local native gateway process with synthetic slot batches. Risk: medium. Depends on tickets 3 and 5.
28. P2 | Evaluate whether Port IPC latency is acceptable for expected slot cadence. Risk: high. Depends on ticket 27.
29. P2 | Draft Erlang module candidates for transport-heavy code paths. Risk: low. Depends on ticket 14.
30. P2 | Define `cumac_scheduler` adapter contract and compatibility rules. Risk: medium. Depends on `ran_scheduler_host`.
31. P2 | Extend config model for multi-cell planning without enabling it yet. Risk: low. Depends on ticket 17.
32. P2 | Add richer incident examples for gateway timeout, drain failure, and rollback failure. Risk: low. Depends on `examples/incidents`.
33. P2 | Define artifact retention and naming policy. Risk: low. Depends on ticket 10.
34. P2 | Initialize CI for format, compile, and doc presence checks. Risk: low. Depends on tickets 2 and 16.
35. P2 | Initialize git repo, commit baseline, and add branch policy. Risk: low. Depends on team acceptance of this bootstrap.
