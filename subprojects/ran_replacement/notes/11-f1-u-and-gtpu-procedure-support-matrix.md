# F1-U And GTP-U Procedure Support Matrix

Status: draft

This note captures the milestone-1 user-plane subset for the `n79_single_ru_single_ue_lab_v1` replacement target.
The focus is not broad feature parity.
The focus is the minimum standards-correct user-plane path needed for one real UE, one real RU, one real `Open5GS` core, and one attach-plus-ping proof path.

## Procedure Support Matrix

| Procedure / path element | Purpose | Milestone-1 status | Evidence | Rollback relevance | Non-goals |
| --- | --- | --- | --- | --- | --- |
| `F1-U` bearer path from CU-UP to DU | Carry user-plane packets for the declared UE session | Required | User-plane forwarding state, tunnel state snapshot, ping result | If this path fails, rollback must restore the prior forwarding state or cleanly remove the cutover state | Multi-UE scaling, multi-cell data-plane, vendor-specific forwarding internals |
| `GTP-U` tunnel establishment and TEID mapping | Bind the UE session to the user-plane tunnel that reaches the real core path | Required | Tunnel creation logs, TEID association snapshot, verify summary | Rollback must clear or revert tunnel state without leaving stale TEIDs or half-open forwarding state | Full GTP-U feature coverage, exotic tunnel topologies, handover behavior |
| Downlink forwarding path | Deliver core-originated traffic to the UE for session validation | Required | Forwarding snapshot, packet-flow evidence, ping response | Cutover rollback must stop forwarding on the new path and return to the prior path | QoS feature parity beyond the lab profile, multi-bearer optimization |
| Uplink forwarding path | Return UE traffic to the core so attach and ping are round-trip valid | Required | Uplink path snapshot, session log, ping success from the declared route | Rollback must remove the active uplink path cleanly so the previous state can be re-established | Multi-UE uplink aggregation, advanced traffic shaping |
| Session-to-tunnel association | Keep the UE session, forwarding state, and tunnel state aligned | Required | Session snapshot, health checks, evidence bundle | Rollback must preserve a deterministic session state transition that can be audited | Session mobility, handover, roaming, cross-lab portability |
| User-plane failure detection | Expose missing or broken forwarding as actionable operator state | Required | Verify failure reason, incident summary, artifact bundle | Rollback relevance is high because failed user-plane cutover must be explainable and reversible | Broad observability parity, deep packet inspection features |

## Milestone-1 Contract

The milestone-1 user-plane contract is satisfied only if the replacement lane can:

1. establish the declared `F1-U` and `GTP-U` path for one real UE,
2. forward traffic to and from the real `Open5GS` core,
3. prove ping success on the declared route,
4. emit evidence that distinguishes success, partial failure, and rollback,
5. restore a clean prior state when cutover fails.

## Explicit Non-Goals

This note does not claim:

- full user-plane protocol parity beyond the declared lab subset
- multi-UE or multi-RU throughput scaling
- handover
- roaming
- production traffic engineering
- deep vendor-specific implementation details
- replacing the real `Open5GS` core in this track

If the replacement lane cannot explain the user-plane path in terms of `F1-U`, `GTP-U`, tunnel state, and evidence-backed rollback, it is not ready for milestone 1.
