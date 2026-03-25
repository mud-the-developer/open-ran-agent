# ran-rollback-change

## Use When

- verification fails
- operator cancels a change inside the TTL window
- backend switch causes degraded service

## Inputs

- `change_id`
- `cell_group`
- `reason`

## Procedure

1. Confirm the rollback target from the saved plan.
2. Run `scripts/run.sh rollback ...` or `bin/ranctl rollback ...`.
3. Run `scripts/run.sh verify ...` or `bin/ranctl verify ...`.
4. Run `scripts/run.sh capture-artifacts ...` or `bin/ranctl capture-artifacts ...` if recovery is incomplete.

## Guardrails

- roll back only to known-good pre-provisioned state
- preserve incident evidence after rollback
