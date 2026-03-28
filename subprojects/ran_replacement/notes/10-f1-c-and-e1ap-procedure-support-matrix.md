# F1-C And E1AP Procedure Support Matrix

Status: draft

## Purpose

This note records the milestone-1 control-plane subset for the replacement track on the `n79_single_ru_single_ue_lab_v1` profile.

The goal is not full `F1-C` or `E1AP` parity. The goal is to make the exact supported procedures, their purpose, their evidence surface, and their rollback relevance explicit before implementation expands.

## Milestone-1 Procedure Matrix

| Procedure | Purpose | Milestone-1 Status | Evidence | Rollback Relevance |
| --- | --- | --- | --- | --- |
| `F1-C` association and setup | Establish the CU-CP and DU control-plane relationship for the declared lab profile. | Required | Association state, peer identity, setup response, protocol health markers. | Required. Failed setup must leave a clean cleanup path. |
| `F1-C` configuration exchange | Carry the DU and cell configuration needed for the declared `n79` profile. | Required | Applied config snapshot, accepted config delta, target-profile identifiers. | Required. Misconfiguration must be reversible or explicitly blocked. |
| `F1-C` cell and serving-cell control | Own the cell-state transitions needed for bring-up and stable attach. | Required | Cell state, activation markers, readiness checks, operator-facing state. | Required. Cell bring-up and cell drain must both be observable. |
| `F1-C` UE context creation | Create the UE context needed for access and registration progress. | Required | UE context identifiers, context state, attach progress markers. | Required. Context creation failure must cleanly release partial state. |
| `F1-C` UE context release | Release UE state after failure, cleanup, or cutover. | Required | Release markers, context teardown evidence, failure cause. | Required. This is the primary cleanup path for rollback. |
| `F1-C` re-establishment guard | Prove the lane can explain when UE context is ready for a bounded retry after cleanup. | Required | Re-establishment marker, post-release peer state, and evidence that the lane returned to a retry-safe control state. | High. This keeps rollback-safe retry explicit instead of inferred from raw logs. |
| `F1-C` UE context modification (single-lane handover-adjacent refresh) | Refresh UE context inside the declared DU and serving-cell ownership path without claiming mobility transfer. | Required | Modification markers, delta summary, and evidence that the refreshed state still matches the target profile and remains rollback-auditable. | Medium. This is the first handover-adjacent claim, but it must stay inside the existing single-lane topology. |
| `F1-C` reset-driven recovery | Provide a bounded escape hatch when the control-plane relationship is stale or half-open. | Optional | Explicit reset intent, post-reset peer state, and cleanup evidence that shows whether the lane returned to a known-safe state. | High. Must stay explicit because it is a recovery tool, not a happy-path milestone gate. |
| `F1-C` handover context transfer | Move UE control between DU or cell contexts. | Deferred | None for milestone 1 beyond a non-claim entry in the support matrix. | Low. Outside the single-cell, single-DU lane. |
| `F1-C` multi-DU context coordination | Coordinate UE state across more than one DU ownership boundary. | Deferred | None for milestone 1. | Low. Topology expansion work must stay separate from the declared lane. |
| `E1AP` association and setup | Establish the CU-CP and CU-UP control-plane relationship for the declared profile. | Required | Association state, peer identity, setup response, protocol health markers. | Required. Failed setup must not leave the data plane half-open. |
| `E1AP` bearer or activity-state coordination | Coordinate control-plane state needed for registration and session establishment. | Required | Bearer/activity-state markers, session progression, control-plane health. | Required. A failed transition must be reversible. |
| `E1AP` bearer-context release | Support cutover, drain, and recovery behavior without hiding stale state. | Required | Release markers, cleared bearer ownership, and peer state after the release transition. | Required. This is one of the main cleanup surfaces for safe switchover and rollback. |
| `E1AP` bearer-context re-establishment | Prove the CU-CP and CU-UP path can explain a bounded retry after release or rollback. | Required | Re-establishment markers, restored peer state, and evidence that bearer ownership is again reviewable on the declared lane. | High. This keeps retry-safe recovery explicit instead of implied by a healthy-looking lane summary. |
| `E1AP` bearer context modification (single-lane handover-adjacent refresh) | Refresh bearer ownership inside the declared CU-CP/CU-UP path without claiming mobility transfer or multi-path routing. | Required | Modification markers, resulting bearer state, and evidence that the refreshed state remains auditable for rollback and replay. | Medium. This is the first handover-adjacent E1AP claim and must stay within the single-lane topology. |
| `E1AP` multi-CU-UP path re-route | Re-anchor the user-plane relationship across CU-UP paths beyond the declared lane. | Deferred | None for milestone 1. | Low. Multi-path coordination is out of scope until topology expansion. |
| `E1AP` handover bearer transfer | Carry bearer ownership through mobility-specific control-path changes. | Deferred | None for milestone 1. | Low. Mobility claims stay deferred outside the declared attach-plus-ping lane. |

## Evidence Expectations

For milestone 1, each supported procedure must produce evidence that can answer:

1. Did the association succeed?
2. Did the declared configuration reach the target profile?
3. Did attach progress reach the point needed for real registration?
4. Did release or rollback leave the control plane clean?

The evidence surface should remain usable by:

- `ranctl`
- the dashboard
- incident review
- later cutover readiness checks

The support matrix should keep the classification explicit:

- `required` procedures are the currently claimed control-plane subset for the declared lane
- `optional` procedures may appear in evidence or recovery without becoming part of the required pass path
- `deferred` procedures remain outside scope until separately evidenced on the same declared lane

For the first handover-adjacent transitions, `required` still does not mean mobility support:

- the claim stays inside one DU, one serving-cell lane, and one CU-UP path
- the evidence must show context or bearer refresh without implying source-target transfer

## Rollback Relevance

Rollback is not an afterthought for this subset.

For milestone 1, the following must be true:

- `F1-C` and `E1AP` setup failures must leave a deterministic cleanup path.
- Partial association or partial configuration must be visible, not hidden.
- `F1-C` release, re-establishment guard, and single-lane context refresh must be explicit evidence points.
- `E1AP` bearer release, re-establishment, and single-lane bearer refresh must be explicit evidence points.
- A cutover attempt without a rollback target is out of scope.

## Non-Goals

This note does not claim:

- full `F1-C` procedure parity
- full `E1AP` procedure parity
- handover transfer across a new DU, CU-UP path, or serving-cell ownership boundary
- multi-cell control-plane scaling
- multi-CU or multi-CU-UP topologies
- mobility management beyond the declared target profile
- vendor-specific extensions outside the supported subset
- replacement of the real `Open5GS` core
- RT hot-path implementation details
