# Backend Switch Failure Example

## Scenario

- `cell_group`: `cg-001`
- `change_id`: `chg-20260320-001`
- attempted target: `local_fapi_profile`
- failure point: verify phase

## Expected Response

1. capture artifacts
2. trigger rollback
3. verify rollback health
4. leave incident record linked to both artifact bundles
