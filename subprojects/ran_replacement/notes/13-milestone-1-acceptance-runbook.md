# Milestone 1 Acceptance Runbook

Status: draft

## Goal

Define the operator runbook for the milestone-1 replacement lane:

- one `n79` profile
- one real RU
- one real UE
- one real `Open5GS` core
- one attach-plus-ping path
- one replacement lane that owns the declared `OAI`-visible CU/DU function chain

This note is the execution companion to the standards evidence note.
It describes the operator sequence, the evidence to inspect at each step,
the soak expectations, the failure classes, and the first debug artifacts to
collect when the run does not pass.

## Runbook Inputs

Before running the lane, the operator must have:

- the declared target profile name
- the real `Open5GS` core profile
- the target-host inventory
- the RU readiness profile
- the UE readiness profile
- the rollback target
- the approval gate required for mutation
- the request payload for the intended action

The runbook assumes the request payload is already sanitized and points to the
declared lab profile, not to ad hoc local-only values.

## Operator Sequence

### 1. `precheck`

Purpose:

- prove the lane is describable and safe enough to plan

What to inspect:

- `gate_class`
- `target_profile`
- `core_profile`
- `core_endpoint`
- `ru_profile`
- `ue_profile`
- `rollback_target`
- per-interface gate state for `NGAP`, `F1-C`, `E1AP`, `F1-U`, and `GTP-U`
- any `blocked` or `degraded` reasons

Pass condition:

- the lane is not blocked
- the real `Open5GS` endpoint is named
- the RU and UE assumptions are explicit
- the rollback target is explicit

Failure action:

- do not proceed to plan if the lane is blocked
- collect the `precheck` artifact and resolve the first missing gate

### 2. `plan`

Purpose:

- describe the intended mutation and the rollback path before any change

What to inspect:

- affected resource
- expected interfaces
- `ngap_subset` references plus required, bounded-claim, and deferred procedure lists when `ngap` is declared
- expected artifacts
- approval requirement
- rollback path
- the next operator-safe step

Pass condition:

- the plan names the same target profile as `precheck`
- the plan does not invent an interface or runtime path that `precheck` did not declare

Failure action:

- stop if the plan depends on a gate that `precheck` marked blocked
- keep the plan artifact for later comparison

### 3. `apply`

Purpose:

- execute the approved mutation with the declared rollback target

What to inspect:

- approval evidence
- current backend or runtime switch decision
- the first interface to change state
- whether the action remained within the approved blast radius

Pass condition:

- the applied state matches the plan
- the run remains inside the declared scope
- no unapproved backend switch occurs

Failure action:

- if the lane diverges from the approved plan, stop and capture evidence
- if the cutover is unsafe, prepare rollback immediately

### 4. `verify`

Purpose:

- prove whether the lane is now standards-correct enough to continue or whether it should be rolled back

What to inspect:

- latest per-interface gate class
- `failure_class`
- `core_endpoint`
- `ngap_subset`
- `core_link_status`
- `ngap_procedure_trace`
- `release_status`
- whether attach progressed to registration
- whether PDU session evidence exists
- whether ping evidence exists
- whether the current state is safe to leave running

Pass condition:

- the standards evidence note resolves to `pass`
- the attach-plus-ping path is complete for the declared profile

Failure action:

- if registration or ping is incomplete, do not call the lane healthy
- keep the verify artifact for replay

### 5. `capture-artifacts`

Purpose:

- freeze the evidence that justified the decision

What to capture:

- `precheck` output
- `plan` output
- `apply` output
- `verify` output
- the declared `ngap_subset`
- the resolved `failure_class`
- interface-specific logs or snapshots
- rollback evidence when the gate is not `pass`

Pass condition:

- a reviewer can explain the first failure without SSH archaeology

Failure action:

- if the artifact set cannot explain the decision, the run is not finished

### 6. `rollback`

Purpose:

- return the lane to the declared rollback target when the evidence says it is safer than leaving the lane up

What to inspect:

- rollback target
- post-rollback verification result
- whether the pre-cutover state was restored cleanly

Pass condition:

- rollback returns the lane to the declared target
- the post-rollback state is auditable and explained

Failure action:

- if rollback cannot be justified from evidence, the lane should have been blocked earlier

## Evidence Checklist

For the declared milestone-1 profile, the operator should expect the following
evidence categories:

- host preflight
- RU sync or RU readiness
- `NGAP` registration evidence
- `F1-C` control-plane evidence
- `E1AP` coordination evidence
- `F1-U` forwarding evidence
- `GTP-U` tunnel and ping evidence
- rollback target and rollback result

The first run is not complete unless each category can be traced to a request,
an artifact, or a sanitized log reference.

## Soak Expectations

Milestone 1 should not be treated as "passed" by a transient success alone.
The run should satisfy the declared soak window for the profile.

Minimum expectations:

- the lane stays stable for the declared verify window
- attach remains reproducible during the window
- user-plane forwarding does not collapse after the first session
- the runtime does not require repeated emergency intervention

The exact soak duration belongs in the target profile and the request payload.
This runbook only says that the soak window must exist and must be captured.

## Failure Classes

Every failure-facing status or artifact should expose one explicit value from:

- `ru_failure`
- `core_failure`
- `user_plane_failure`
- `cutover_or_rollback_failure`

### RU Failure

Use when the lane cannot reach a stable RU sync state.

Typical evidence:

- missing or unstable sync
- missing timing source
- wrong RU transport assumptions

First artifacts:

- host preflight output
- RU readiness artifact
- the failing request payload

### Core Failure

Use when the real `Open5GS` core rejects registration or session setup.

Typical evidence:

- NG setup failure
- registration rejection
- PDU session failure
- subscriber, PLMN, TAC, or DNN mismatch

First artifacts:

- `verify` output
- compare report or NGAP procedure trace with the named core endpoint
- core-facing logs or summaries
- `NGAP` procedure evidence

### User-Plane Failure

Use when registration succeeds but ping does not.

Typical evidence:

- PDU session exists
- route or tunnel state is incomplete
- forwarding exists but traffic does not pass

First artifacts:

- `F1-U` snapshot
- `GTP-U` snapshot
- ping result

### Cutover Or Rollback Failure

Use when the lane changed state but did not return cleanly to the declared target.

Typical evidence:

- rollback target missing
- rollback result unclear
- partial state remains live after rollback

First artifacts:

- plan output
- apply output
- rollback output
- post-rollback verify output

## First Debug Artifacts

The first artifacts to inspect should be, in order:

1. `precheck` output
2. `plan` output
3. `verify` output
4. `capture-artifacts` bundle index
5. host preflight summary
6. RU readiness summary
7. core-facing attach and session evidence

If the failure is still ambiguous after those, the operator should inspect the
sanitized incident example that matches the observed failure class.

## Acceptance Rule

This milestone is only accepted when the runbook, the standards evidence note,
and the request/status contracts all agree on the same declared profile and the
same rollback target.

If any one of those disagrees, the run is not a milestone-1 pass.
