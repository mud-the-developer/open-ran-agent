# ran-drain-cell-group

## Use When

- a backend gateway needs restart
- a cell-group needs controlled maintenance
- rollback requires traffic drain first

## Inputs

- `cell_group`
- `change_id`
- `verify_window`

## Procedure

1. Run `scripts/run.sh precheck ...` or `bin/ranctl precheck ...`.
2. Run `scripts/run.sh plan ...` or `bin/ranctl plan ...`.
3. Obtain explicit approval.
4. Run `scripts/run.sh apply ...` or `bin/ranctl apply ...`.
5. Run `scripts/run.sh verify ...` or `bin/ranctl verify ...`.
6. If verification fails, call `ran-rollback-change`.

## Guardrails

- never drain a wider scope than declared in `max_blast_radius`
