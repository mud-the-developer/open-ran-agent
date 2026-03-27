# F1-U And GTP-U Procedure Support Matrix

Status: draft

This note captures the milestone-1 user-plane subset for the `n79_single_ru_single_ue_lab_v1` replacement target.
The focus is not broad feature parity.
The focus is the minimum standards-correct user-plane path needed for one real UE, one real RU, one real `Open5GS` core, and one attach-plus-ping proof path.

## Procedure Support Matrix

| Procedure / path element | Purpose | Milestone-1 status | Evidence | Rollback relevance | Non-goals |
| --- | --- | --- | --- | --- | --- |
| `F1-U` bearer path establishment | Carry user-plane packets from `CU-UP` to `DU` for the declared UE session. | Required | Forwarding state snapshot, bearer identity, and attach-plus-ping evidence that names the declared lane. | If this path fails, rollback must restore the prior forwarding state or cleanly remove the cutover state. | Multi-UE scaling, multi-cell data-plane, vendor-specific forwarding internals |
| `F1-U` downlink forwarding path | Deliver core-originated traffic to the UE for session validation. | Required | Downlink forwarding snapshot, packet-flow evidence, and ping response. | Cutover rollback must stop forwarding on the new path and return to the prior path. | QoS feature parity beyond the lab profile, multi-bearer optimization |
| `F1-U` uplink forwarding path | Return UE traffic to the core so attach and ping are round-trip valid. | Required | Uplink path snapshot, session log, and ping success from the declared route. | Rollback must remove the active uplink path cleanly so the previous state can be re-established. | Multi-UE uplink aggregation, advanced traffic shaping |
| `F1-U` failure detection and rollback visibility | Expose missing or broken forwarding as actionable operator state before the lane is left running. | Required | Verify failure reason, incident summary, compare report, and rollback evidence bundle. | High. Failed user-plane cutover must be explainable and reversible. | Broad observability parity, deep packet inspection features |
| `F1-U` tunnel update | Adjust a declared forwarding path without widening the lane beyond the single UE session. | Optional | Update markers, pre/post forwarding state, and evidence that the lane stayed auditable. | Medium. Useful for bounded correction, but not required for the first attach-plus-ping proof. | Broad bearer-management parity |
| `F1-U` forwarding relocation during handover | Move forwarding ownership during mobility or topology-change events. | Deferred | None for milestone 1. | Low. Handover remains outside the declared lane. | Mobility parity |
| `F1-U` multi-UE forwarding fan-out | Carry or coordinate more than one active UE forwarding path. | Deferred | None for milestone 1. | Low. Multi-UE behavior is a later topology lane. | Throughput or scaling claims |
| `GTP-U` tunnel establishment and TEID mapping | Bind the UE session to the user-plane tunnel that reaches the real core path. | Required | Tunnel creation logs, TEID association snapshot, and verify summary. | Rollback must clear or revert tunnel state without leaving stale TEIDs or half-open forwarding state. | Full GTP-U feature coverage, exotic tunnel topologies, handover behavior |
| `GTP-U` session-to-tunnel association | Keep the UE session, forwarding state, and tunnel state aligned. | Required | Session snapshot, health checks, and evidence bundle. | Rollback must preserve a deterministic session state transition that can be audited. | Session mobility, handover, roaming, cross-lab portability |
| `GTP-U` downlink route forwarding | Deliver downlink tunnel traffic onto the declared route. | Required | Route snapshot, packet-flow evidence, and ping validation context. | Rollback must stop the new route cleanly before leaving the lane up. | Multi-path steering or broad route-policy claims |
| `GTP-U` uplink route forwarding | Return uplink tunnel traffic toward the declared core path. | Required | Uplink route snapshot, ping evidence, and session log. | Rollback must remove the active route cleanly so the previous state can be re-established. | Advanced traffic engineering |
| `GTP-U` tunnel release and cleanup | Remove or restore tunnel state safely after failure, retry, or rollback. | Required | Release markers, cleanup summary, and post-rollback tunnel state evidence. | High. Stale tunnel state is an explicit rollback risk. | Broad tunnel lifecycle parity beyond the declared lane |
| `GTP-U` tunnel rebind | Rebind the declared tunnel without claiming broad mobility or multi-core support. | Optional | Rebind markers, resulting TEID state, and evidence that the route remains auditable. | Medium. Useful for bounded recovery, but not a required milestone-1 proof path. | Broad re-anchoring parity |
| `GTP-U` path-switch re-anchoring | Move tunnel anchoring after mobility or broader topology change. | Deferred | None for milestone 1. | Low. Path switch stays outside the single declared lane. | Mobility parity |
| `GTP-U` multi-path tunnel steering | Steer traffic across multiple declared tunnel paths. | Deferred | None for milestone 1. | Low. Multi-path behavior is outside the milestone-1 lane. | Advanced user-plane routing claims |

## Milestone-1 Contract

The milestone-1 user-plane contract is satisfied only if the replacement lane can:

1. establish the declared `F1-U` and `GTP-U` path for one real UE,
2. forward traffic to and from the real `Open5GS` core,
3. prove ping success on the declared route,
4. emit evidence that distinguishes success, partial failure, and rollback,
5. restore a clean prior state when cutover fails.

The support matrix should keep the classification explicit:

- `required` path elements are the currently claimed user-plane subset for the declared lane
- `optional` path elements may appear in evidence or bounded recovery without becoming part of the required pass path
- `deferred` path elements remain out of scope until separately evidenced on the same declared lane

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
