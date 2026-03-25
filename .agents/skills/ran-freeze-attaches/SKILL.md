# ran-freeze-attaches

## Use When

- a cell-group or backend is about to change
- attach churn must be paused before drain or rollback

## Inputs

- `cell_group`
- `change_id`
- `reason`

## Procedure

1. Run `scripts/run.sh precheck ...` or `bin/ranctl precheck ...`.
2. Run `scripts/run.sh plan ...` or `bin/ranctl plan ...`.
3. Require approval if service impact is expected.
4. Run `scripts/run.sh apply ...` or `bin/ranctl apply ...`.
5. Run `scripts/run.sh verify ...` or `bin/ranctl verify ...`.

## Guardrails

- treat attach freeze as a service-affecting action
- ensure rollback intent exists before apply
