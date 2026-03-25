# ran-observe

## Use When

- an incident is open
- health needs to be checked before planning a change
- an operator needs a current runtime snapshot

## Inputs

- `scope`
- optional `cell_group`
- optional `incident_id`

## Procedure

1. Confirm the observation scope.
2. Run `scripts/run.sh ...` or `bin/ranctl observe ...`.
3. If the result lacks evidence, hand off to `ran-capture-artifacts`.

## Guardrails

- observation is read-only
- do not mutate runtime state from this skill
