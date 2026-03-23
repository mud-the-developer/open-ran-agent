# ran-capture-artifacts

## Use When

- verification fails
- an incident needs evidence preserved
- a backend switch needs before and after artifacts

## Inputs

- `incident_id` or `change_id`
- `scope`
- optional `cell_group`

## Procedure

1. Confirm artifact scope and retention intent.
2. Run `scripts/run.sh ...` or `bin/ranctl capture-artifacts ...`.
3. Store returned artifact references in the incident or change record.

## Guardrails

- artifact capture is non-mutating
- do not overwrite previous bundles without explicit retention policy
