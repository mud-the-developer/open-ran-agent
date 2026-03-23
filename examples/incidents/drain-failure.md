# Drain Failure Example

## Scenario

- `change_id`: `chg-20260320-010`
- requested action: drain `cell_group` `cg-001`
- failure point: verify detects new attaches are still admitted

## Expected Response

1. capture artifacts for attach admission and scheduler state
2. evaluate whether rollback is needed or whether a second drain is safe
3. preserve the failed verification bundle under the incident record
