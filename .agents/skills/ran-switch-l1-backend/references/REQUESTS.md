# ran-switch-l1-backend Reference

## Canonical Plan Request

```json
{
  "scope": "cell_group",
  "cell_group": "cg-001",
  "target_backend": "local_fapi_profile",
  "change_id": "chg-20260320-001",
  "reason": "switch to pre-provisioned local backend",
  "idempotency_key": "cg-001-switch-local-001",
  "verify_window": {
    "duration": "30s",
    "checks": ["gateway_healthy", "cell_group_attached", "ue_ping_ok"]
  },
  "max_blast_radius": "single_cell_group"
}
```

## Guardrail

`plan` and `precheck` must reject targets that are not listed in configured `failover_targets`.
