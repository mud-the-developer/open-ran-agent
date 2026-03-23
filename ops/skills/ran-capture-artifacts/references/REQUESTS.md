# ran-capture-artifacts Reference

## Canonical Capture Request

```json
{
  "scope": "incident",
  "incident_id": "inc-20260320-050",
  "reason": "capture evidence after failed verify",
  "idempotency_key": "inc-20260320-050-capture",
  "verify_window": {
    "duration": "0s",
    "checks": []
  }
}
```

## Expected Result

- `status: captured`
- a bundle reference under `artifacts/captures/`
