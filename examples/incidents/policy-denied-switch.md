# Policy Denied Switch Example

## Scenario

- `cell_group`: `cg-001`
- requested target: backend not listed in configured `failover_targets`
- failure point: `plan` phase rejects the request

## Expected Response

1. return `policy_denied`
2. include allowed targets and rollback target in the response
3. do not write an apply state artifact
