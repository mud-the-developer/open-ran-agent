# Gateway Health Timeout Example

## Scenario

- `incident_id`: `inc-20260320-001`
- symptom: native gateway health probe stays degraded
- preferred action: gateway-local recovery before cell-group restart

## Suggested Skill Path

1. `ran-observe`
2. `ran-capture-artifacts`
3. `ran-restart-fapi-gateway`
4. `ran-rollback-change` if a related change is active
