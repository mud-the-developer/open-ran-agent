# ran-rollback-change Reference

## Canonical Rollback Request

```json
{
  "scope": "cell_group",
  "cell_group": "cg-001",
  "change_id": "chg-20260320-001",
  "incident_id": "inc-20260320-001",
  "reason": "rollback failed backend switch",
  "idempotency_key": "cg-001-rollback-001",
  "approval": {
    "approved": true,
    "source": "incident-operator"
  },
  "verify_window": {
    "duration": "45s",
    "checks": ["gateway_healthy", "rollback_target_active"]
  }
}
```

## Expected Result

- `status: rolled_back`
- `target_backend` set to the saved rollback target
- follow-up `verify` required
