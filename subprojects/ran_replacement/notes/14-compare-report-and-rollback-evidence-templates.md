# Compare Report And Rollback Evidence Templates

Status: draft

## Goal

Define the reusable evidence templates that make `verify` and `capture-artifacts`
auditable for the milestone-1 replacement lane.

The milestone-1 lane is fixed:

- one `n79` profile
- one real RU
- one real UE
- one real `Open5GS` core
- one attach-plus-ping path
- one replacement lane that owns the declared `OAI`-visible CU/DU function chain

This note does not define runtime behavior. It defines the shape of the
comparison report and rollback evidence so operators can explain why a gate
resolved to `blocked`, `degraded`, or `pass`.

## Why Templates Matter

The replacement track needs more than logs.

For every operator-visible transition, the lane should be able to answer:

- what changed
- what stayed the same
- what evidence proved the decision
- what rollback target was chosen
- what first failed when the lane did not pass

The compare report is the operator-facing summary of "current versus expected".
The rollback evidence is the operator-facing summary of "why rollback was the
safer action and what restored state was observed after it".

## Template 1: Compare Report

The compare report should be emitted whenever `verify` or `capture-artifacts`
needs to compare the declared target profile against live state.

Minimum sections:

- `report_id`
- `change_id`
- `incident_id`
- `target_profile`
- `core_profile`
- `core_endpoint`
- `comparison_scope`
- `expected_state`
- `observed_state`
- `gate_class`
- `failure_class`
- `ngap_subset`
- `diff_summary`
- `evidence_refs`
- `rollback_target`
- `operator_next_step`

### Compare Report Rules

- The report must name the declared profile, not a local-only alias.
- The report must name the declared core endpoint and profile, not just a generic core label.
- The report must say which interface family is being compared.
- The report must carry the declared NGAP subset references when NGAP-facing evidence is involved.
- The report must distinguish `expected` from `observed`.
- The report must call out whether a mismatch is functional, procedural, or
  evidence-related.
- The report must be readable without SSH access.

## Template 2: Rollback Evidence

The rollback evidence template should be emitted when the lane is rolled back
or when rollback is the safer decision but has not yet been executed.

Minimum sections:

- `rollback_id`
- `change_id`
- `incident_id`
- `target_profile`
- `rollback_target`
- `rollback_reason`
- `triggering_gate`
- `failure_class`
- `ngap_subset`
- `pre_rollback_state`
- `post_rollback_state`
- `recovery_check`
- `evidence_refs`
- `operator_notes`

### Rollback Evidence Rules

- The rollback evidence must say why rollback was safer than leaving the lane
  up.
- The rollback evidence must reference the compare report that triggered the
  decision.
- The rollback evidence must preserve the same NGAP subset references and failure class that justified the decision.
- The rollback evidence must show whether the rollback target was restored
  cleanly.
- The rollback evidence must not rely on implicit operator memory.

## Interface Coverage

The compare report and rollback evidence templates must support all interfaces
that matter for milestone 1:

### `NGAP`

Compare:

- setup state against the real `Open5GS` core
- registration progression versus expected attach path
- named NGAP procedure checkpoints from `NG Setup` through `UE Context Release`
- release state versus expected cleanup state

Rollback:

- report whether the NGAP path was restored to the declared rollback target
- note whether registration attempts are safe to retry

### `F1-C`

Compare:

- CU-CP and DU association state
- setup or re-establishment state
- configuration acceptance state
- release state versus rollback expectations

Rollback:

- note whether the control-plane association returned to the rollback target
- note whether pending UE context state was cleared or retained by design

### `E1AP`

Compare:

- CU-CP and CU-UP association state
- setup or re-establishment state
- bearer or activity coordination state
- release state versus rollback expectations

Rollback:

- note whether CU-UP coordination returned to the rollback target
- note whether user-plane coordination can be retried safely

### `F1-U`

Compare:

- forwarding state
- tunnel or forwarding association
- UE session to tunnel binding
- evidence that user-plane traffic can flow

Rollback:

- note whether forwarding was drained or restored cleanly
- note whether the user-plane path is safe for another attach attempt

### `GTP-U`

Compare:

- tunnel creation or TEID mapping
- downlink and uplink route state
- session binding
- ping reachability on the declared route

Rollback:

- note whether the tunnel state was reset or preserved as planned
- note whether ping failure was caused by data-plane state or a separate issue

### RU Sync

Compare:

- sync lock or equivalent healthy indicator
- transport assumptions
- timing source assumptions
- host-device mapping

Rollback:

- note whether the RU was brought back to the known-good sync target
- note whether the failure came from host readiness or RU behavior

### Registration

Compare:

- subscriber identity
- PLMN, TAC, and DNN assumptions
- NGAP procedure support
- registration progression versus the target profile

Rollback:

- note whether the registration attempt left the core in a clean state
- note whether a retry is safe after profile correction

### PDU Session

Compare:

- session creation state
- address or route allocation
- DNN and slice assumptions
- session binding to the declared UE

Rollback:

- note whether the session was torn down cleanly
- note whether the lane should retry with the same or a corrected profile

### Ping

Compare:

- declared ping target
- observed latency or loss outcome
- route or tunnel state at the time of the probe

Rollback:

- note whether ping failure is attributable to user-plane state or a broader
  lane failure
- note whether another run is safe without extra rollback

## How `verify` Uses The Templates

`verify` should read the compare report template, not invent its own one-off
summary.

`verify` should populate, at minimum:

- `comparison_scope`
- `expected_state`
- `observed_state`
- `gate_class`
- `diff_summary`
- `evidence_refs`
- `rollback_target`

For milestone 1, `verify` should be able to answer:

- whether the lane is still `blocked`, `degraded`, or `pass`
- which interface first diverged from the expected profile
- whether the divergence is in NGAP, F1-C, E1AP, F1-U, GTP-U, RU sync,
  registration, PDU session, or ping
- whether rollback is now the safer operator action

## How `capture-artifacts` Uses The Templates

`capture-artifacts` should preserve both templates together when the lane fails
or when the operator needs a replayable proof set.

It should capture, at minimum:

- the compare report
- the rollback evidence
- the request payload that triggered the run
- the verify output that resolved the gate
- any interface-specific snapshots or logs referenced by the templates

For milestone 1, a captured artifact set should let a reviewer reconstruct:

- the expected state
- the observed state
- the first mismatch
- the rollback target
- the recovery result

## Operator Use

Operators should use the templates in this order:

1. Inspect the compare report to understand the mismatch.
2. Decide whether the lane is safe to continue or should roll back.
3. If rollback occurs, inspect the rollback evidence to confirm restoration.
4. Store both artifacts in the capture bundle so the decision can be replayed.

The point is to keep the decision chain deterministic:

- `precheck` says whether planning is safe
- `verify` says whether the current state matches the declared profile
- `capture-artifacts` preserves the evidence
- rollback evidence explains the restoration path

## Non-Goals

This note does not claim:

- runtime implementation of the compare report
- runtime implementation of rollback orchestration
- full protocol parity beyond the milestone-1 subset
- multi-cell or multi-RU behavior
- vendor-specific log schemas

The purpose of this note is to make `verify` and `capture-artifacts`
operationally legible for the replacement track without hiding the decision
logic in ad hoc logs.
