# ADR 0007: RAN Functions As Agent-Friendly CLI Surface

## Status

Accepted

## Context

The repository already routes mutable operator actions through `bin/ranctl`, but the next replacement-oriented RAN track will need a broader operator surface:

- gNB bring-up and teardown
- CU and DU scoped actions
- RU and RU-link readiness
- target-host readiness
- UE session handling
- evidence capture and rollback

If these functions are exposed through ad hoc scripts, component-specific wrappers, or UI-only actions, the repository loses the properties that make it operable:

- deterministic auditability
- reusable agent control
- reusable dashboard control
- approval-gated destructive actions
- stable artifact output

At the same time, "everything is a shell command" is also the wrong model for a RAN system because slot-paced and RT-sensitive work cannot be reduced to per-tick CLI operations.

## Decision

Use an agent-friendly CLI surface for operator-visible RAN functions, but keep the CLI as a control-plane façade over canonical request contracts.

This means:

- mutable operator-visible actions stay under `bin/ranctl`
- short human-facing commands may exist, but they map to canonical JSON requests and the same runner semantics
- actions are modeled by `resource + action`, not an unbounded list of one-off verbs
- every CLI path that mutates state must expose stable machine-readable output
- slot-paced, scheduler-paced, and RT-sensitive datapaths remain BEAM internals or native worker internals, not per-slot CLI commands

The CLI surface should separate actions into three classes:

- read-only:
  - `get`
  - `list`
  - `observe`
  - `verify`
- reversible mutate:
  - `drain`
  - `resume`
  - `freeze-attaches`
  - `unfreeze-attaches`
  - `reload-config`
  - `capture-artifacts`
- destructive or cutover:
  - `bring-up`
  - `tear-down`
  - `switch-runtime`
  - `cutover`
  - `rollback`

All mutable responses should stabilize around fields such as:

- `status`
- `checks`
- `approval_required`
- `rollback_available`
- `artifacts`
- `suggested_next`

## Consequences

Positive:

- agents, humans, dashboard actions, and remote runners can all drive one surface
- risky operations stay reviewable and approval-gated
- docs, examples, tests, and dashboard payloads can reuse one vocabulary
- cutover and rollback evidence remain consistent across tracks

Negative:

- request and output schema discipline becomes more important
- there is up-front design cost before runtime implementation
- some developer convenience commands must be rejected if they do not fit the canonical contract

## Alternatives Considered

- Expose every function through bespoke shell scripts: rejected because auditability and machine control drift immediately.
- Put rich mutable logic only behind the dashboard UI: rejected because remote automation and non-UI control would diverge.
- Let RT-sensitive loops expose direct fine-grained CLI commands: rejected because that breaks the repository's hot-path boundary discipline.

