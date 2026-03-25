# ran-switch-l1-backend

## Use When

- switching between pre-provisioned backend targets
- moving from stub to local backend in lab
- recovering from a degraded backend gateway

## Inputs

- `cell_group`
- `target_backend`
- `change_id`
- `reason`
- `verify_window`

## Procedure

1. Run `scripts/run.sh precheck ...` or `bin/ranctl precheck ...`.
2. Run `scripts/run.sh plan ...` or `bin/ranctl plan ...`.
3. Review rollback plan.
4. Obtain explicit approval.
5. Run `scripts/run.sh apply ...` or `bin/ranctl apply ...`.
6. Run `scripts/run.sh verify ...` or `bin/ranctl verify ...`.
7. If needed, trigger `ran-rollback-change`.

## Guardrails

- switch only to pre-provisioned targets
- never bypass `ranctl`
