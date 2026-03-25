# RAN Function CLI Taxonomy

Status: draft baseline for agent-friendly control

## Goal

Define a control surface that is easy for:

- humans
- remote automation
- dashboard actions
- agents

while preserving one canonical mutable path.

## Rule

Short commands may exist, but they must compile to the same canonical `ranctl` request model.

The CLI is a façade.
The request contract and runner semantics remain the real source of truth.

## Resource Model

The replacement track should use explicit resources instead of one-off verbs:

- `gnb`
- `cu_cp`
- `cu_up`
- `du`
- `cell`
- `ru`
- `ru_link`
- `ue_session`
- `transport_profile`
- `target_host`

## Action Classes

### Read-only

- `get`
- `list`
- `observe`
- `verify`

These should never require destructive approval.

### Reversible mutate

- `drain`
- `resume`
- `freeze-attaches`
- `unfreeze-attaches`
- `reload-config`
- `capture-artifacts`

These may require policy checks, but should preserve a bounded rollback path.

### Destructive or cutover

- `bring-up`
- `tear-down`
- `switch-runtime`
- `cutover`
- `rollback`

These require explicit approval and rollback semantics.

## Output Contract

Every action that the agent can use should stabilize around:

- `status`
- `checks`
- `approval_required`
- `rollback_available`
- `artifacts`
- `suggested_next`

## Example Human CLI

Examples of the intended shape:

- `ranctl get gnb gnb-001 --json`
- `ranctl observe ru-link ru-link-001 --json`
- `ranctl apply target-host host-001 precheck --json`
- `ranctl apply gnb gnb-001 bring-up --json`
- `ranctl apply cell cell-001 freeze-attaches --json`
- `ranctl apply transport-profile n79-lab switch-runtime --target replacement_du --json`

## Example Canonical Intent

All of the above should resolve to a canonical request with:

- `scope`
- `target`
- `action`
- `metadata`
- `approval`
- `rollback_target`

## Explicit Non-Goals

The CLI is not for:

- per-slot scheduling
- live FAPI message poking in RT loops
- RU sample-timed operations
- hidden internal state mutation outside the request runner

