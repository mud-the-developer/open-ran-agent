# ran-restart-fapi-gateway

## Use When

- gateway health is degraded
- transport state must be reinitialized without a full node restart

## Inputs

- `cell_group`
- `incident_id`
- optional `change_id`

## Procedure

1. Observe current gateway health through `scripts/run.sh observe ...` or `bin/ranctl observe ...`.
2. Run `scripts/run.sh precheck ...` or `bin/ranctl precheck ...`.
3. Plan the restart and verify blast radius.
4. Obtain approval if service impact exists.
5. Apply and verify through `scripts/run.sh apply ...` and `scripts/run.sh verify ...`.

## Guardrails

- prefer gateway-local recovery before cell-group restart
- capture artifacts if health does not recover
