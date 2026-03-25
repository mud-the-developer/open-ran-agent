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
| `E1AP` association and setup | Establish the CU-CP and CU-UP control-plane relationship for the declared profile. | Required | Association state, peer identity, setup response, protocol health markers. | Required. Failed setup must not leave the data plane half-open. |
| `E1AP` bearer or activity-state coordination | Coordinate control-plane state needed for registration and session establishment. | Required | Bearer/activity-state markers, session progression, control-plane health. | Required. A failed transition must be reversible. |
| `E1AP` release and re-establishment | Support cutover, drain, and recovery behavior without hiding stale state. | Required | Release markers, re-establishment markers, peer state after transition. | Required. This is required for safe switchover and rollback. |

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

## Rollback Relevance

Rollback is not an afterthought for this subset.

For milestone 1, the following must be true:

- `F1-C` and `E1AP` setup failures must leave a deterministic cleanup path.
- Partial association or partial configuration must be visible, not hidden.
- Context release and re-establishment must be explicit evidence points.
- A cutover attempt without a rollback target is out of scope.

## Non-Goals

This note does not claim:

- full `F1-C` procedure parity
- full `E1AP` procedure parity
- handover
- multi-cell control-plane scaling
- multi-CU or multi-CU-UP topologies
- mobility management beyond the declared target profile
- vendor-specific extensions outside the supported subset
- replacement of the real `Open5GS` core
- RT hot-path implementation details

