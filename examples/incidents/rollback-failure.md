# Rollback Failure Example

## Scenario

- `change_id`: `chg-20260320-011`
- rollback target: `stub_fapi_profile`
- failure point: post-rollback verify does not restore expected health

## Expected Response

1. capture artifacts immediately
2. freeze further changes on the affected `cell_group`
3. escalate to manual operator review with both plan and rollback artifacts attached
