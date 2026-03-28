# Standards Evidence And Acceptance Gates

Status: draft

## Goal

Define the evidence gates that decide whether the milestone-1 replacement lane is standards-correct enough to proceed for the declared `n79_single_ru_single_ue_lab_v1` profile.

The milestone-1 scope is fixed:

- one real `n79` lab profile
- one real RU
- one real UE
- one real `Open5GS` core
- one attach-plus-ping path
- one replacement lane that owns the declared `OAI`-visible CU/DU function chain

This note does not define runtime implementation. It defines what the operator must be able to prove before `ranctl` may move from preflight to cutover, and what must be captured when a run fails.

## Gate Classes

Every milestone-1 run must resolve to exactly one of these classes per declared scope:

- `blocked`
- `degraded`
- `pass`

### `blocked`

`blocked` means the declared scope is not safe to mutate.

Use `blocked` when any required interface is missing, any required evidence is absent, any rollback target is unknown, or any standards-correct behavior for the supported subset is not demonstrated.

Operator rule:

- `ranctl precheck` must fail the gate
- `ranctl plan` must not promise cutover
- `ranctl apply` must not proceed without an explicit override path that still preserves approval gating

### `degraded`

`degraded` means the lane is visible and partially alive, but not safe for milestone-1 cutover.

Use `degraded` when:

- the control-plane or user-plane is shadowing only
- one or more bounded recovery claims are not yet evidenced on their declared review lanes
- the lane can explain state and capture evidence, but attach-plus-ping is not yet proven end to end

Operator rule:

- `ranctl plan` may describe the next safe step
- `ranctl verify` must not label the lane ready for cutover
- `ranctl capture-artifacts` must preserve the partial evidence set

### `pass`

`pass` means the declared scope is ready for the next destructive or cutover-capable step.

Use `pass` only when:

- the required interface subset is standards-correct for the supported scope
- the evidence surface names the core endpoint, RU state, UE state, and rollback target
- the lane can prove attach-plus-ping on the declared profile or can prove the exact step needed to reach that proof

Operator rule:

- `ranctl precheck` may allow `plan` to proceed
- `ranctl verify` may mark the declared scope ready for apply or cutover
- `ranctl capture-artifacts` must be able to replay the decision

## Interface Evidence Gates

### `NGAP`

Required evidence for milestone 1:

- `NG Setup` to the real `Open5GS` core
- `Initial UE Message`
- `Uplink NAS Transport`
- `Downlink NAS Transport`
- `UE Context Release`

Bounded recovery claims for the declared lane:

- `Error Indication` on registration-rejection review lanes
- `Reset` on cutover rollback review lanes

Gate expectations:

- `blocked` if the core endpoint is unknown, NG setup fails, or the attach path cannot be identified
- `degraded` if NG setup succeeds but registration has not yet progressed to the declared attach proof
- `pass` if the attach path reaches real registration and the release path is clean or auditable

### `F1-C`

Required evidence for milestone 1:

- CU-CP and DU association state
- setup response or equivalent peer-accepted setup evidence
- target-profile configuration acceptance
- UE context creation and release markers
- clean release or re-establishment markers for rollback

Gate expectations:

- `blocked` if the association or configuration cannot be proven
- `degraded` if the control-plane is shadowing but not yet suitable for cutover
- `pass` if the declared `n79` control-plane subset is standards-correct and can support attach progress

### `E1AP`

Required evidence for milestone 1:

- CU-CP and CU-UP association state
- setup response or equivalent peer-accepted setup evidence
- bearer or activity-state coordination needed for the declared profile
- release and re-establishment evidence for drain or rollback

Gate expectations:

- `blocked` if the CU-UP relationship is missing or half-open
- `degraded` if E1AP is present but not yet sufficient for the attach-plus-ping path
- `pass` if the supported subset is established and cleanly releasable

### `F1-U`

Required evidence for milestone 1:

- user-plane forwarding state from CU-UP to DU
- tunnel or forwarding snapshot for the declared UE session
- session-to-tunnel association
- packet-forwarding evidence that the path is live

Gate expectations:

- `blocked` if forwarding state is absent or inconsistent
- `degraded` if the path exists but ping or session forwarding is not yet proven
- `pass` if the declared path carries the target UE traffic and the forwarding state is auditable

### `GTP-U`

Required evidence for milestone 1:

- tunnel creation or TEID mapping state
- association between the UE session and the tunnel
- downlink and uplink forwarding evidence
- ping outcome on the declared route

Gate expectations:

- `blocked` if the tunnel state is missing or stale
- `degraded` if the tunnel exists but the route is not yet proven end to end
- `pass` if the tunnel is active, the session is bound, and ping works on the declared path

## Command-Level Artifacts

### `precheck`

`precheck` must answer whether the declared scope is safe to plan.

It must surface, at minimum:

- `gate_class`
- `failure_class`
- `target_profile`
- `core_profile`
- `core_endpoint`
- `ru_profile`
- `ue_profile`
- `rollback_target`
- `protocol_claims.ngap`
- `protocol_claims.f1_c`
- `protocol_claims.e1ap`
- `protocol_claims.f1_u`
- `protocol_claims.gtpu`
- per-interface gate state for `NGAP`, `F1-C`, `E1AP`, `F1-U`, and `GTP-U`
- a list of reasons for any `blocked` or `degraded` result

`precheck` must fail closed when:

- the real `Open5GS` core endpoint is missing
- the RU readiness is unknown
- the UE path is not defined
- the rollback target is missing
- any required interface has no standards-correct evidence path

### `verify`

`verify` must answer whether the lane is in a state that can proceed to apply, cutover, or rollback.

It must surface, at minimum:

- the latest per-interface gate class
- `failure_class`
- `core_endpoint`
- `protocol_claims`
- `core_link_status`
- `ngap_procedure_trace`
- the last observed procedure or state transition per interface
- `release_status`
- whether attach progressed to registration
- whether PDU session and ping evidence exist
- whether the current state is safe to leave running or should be rolled back

`verify` must fail closed when:

- the attach-plus-ping path is incomplete
- the evidence is stale or partial
- cleanup or release evidence is missing
- any required standards subset cannot be named explicitly

### `capture-artifacts`

`capture-artifacts` must preserve the evidence needed to replay the gate decision.

It must capture, at minimum:

- `precheck` output
- `plan` output
- `verify` output
- the declared `protocol_claims` references and procedure lists
- the resolved `failure_class` when the gate is not `pass`
- interface-specific logs or snapshots
- rollback evidence when the gate was not `pass`

For milestone 1, the captured artifacts must allow a reviewer to answer:

- which interface failed first
- whether the failure was control-plane, user-plane, RU, UE, or core-related
- whether rollback was taken
- whether the rollback target was restored cleanly

## Standards-Correct Acceptance Rules

Milestone 1 is not accepted unless all of the following are true for the declared profile:

1. `NGAP` evidence proves real registration against the real `Open5GS` core.
2. `F1-C` evidence proves the declared control-plane subset is established and releasable.
3. `E1AP` evidence proves CU-CP and CU-UP coordination is established and releasable.
4. `F1-U` evidence proves the user-plane path carries the declared UE traffic.
5. `GTP-U` evidence proves the tunnel is bound and ping reaches the declared route.
6. The evidence surface names the rollback target and shows whether it was restored.

If any one of those is missing, the result is not `pass`.

## Mapping To ranctl

`ranctl` should treat the gates as the control contract, not as incidental logs.

- `ranctl precheck` computes the gate class and refuses unsafe cutover planning.
- `ranctl plan` may only describe mutation when `precheck` is not `blocked`, and it must keep the declared `required_procedures`, `bounded_claimed_procedures`, and `deferred_procedures` split explicit rather than implying broader parity.
- `ranctl apply` requires the explicit approval gate already defined by the repo rules.
- `ranctl verify` confirms whether the current state is still standards-correct or whether rollback is now the safer operator action.
- `ranctl capture-artifacts` freezes the evidence that justified the decision.

The important rule is simple:

- `blocked` means stop
- `degraded` means observe or shadow only
- `pass` means the declared milestone-1 step may proceed with approval

## Mapping To Rollback

Rollback must be decided from evidence, not intuition.

Rollback is required when:

- any required interface is `blocked` after a cutover attempt
- attach progresses but registration or ping does not complete
- user-plane state exists without a clean control-plane release path
- the current state cannot be explained in the artifact set

Rollback is not optional when:

- the rollback target is known and the current state is worse than the target
- `capture-artifacts` shows partial state that is not standards-correct for the supported subset
- the interface failure path is ambiguous enough that leaving the lane up would hide risk

The rollback decision should leave behind:

- the failed gate class
- the last observed interface state
- the chosen rollback target
- the post-rollback verification result

## Non-Goals

This note does not claim:

- full protocol parity beyond the milestone-1 subset
- multi-cell or multi-RU proof
- mobility features like handover
- vendor-specific implementation details
- runtime implementation in this note
- replacing the real `Open5GS` core in this track

The purpose of this note is to make the evidence gate honest enough that milestone 1 can be judged consistently and replayed later.
