# ran-observe Reference

## Canonical Request

```json
{
  "scope": "incident",
  "incident_id": "inc-20260320-001",
  "reason": "collect runtime state",
  "idempotency_key": "inc-20260320-001-observe",
  "verify_window": {
    "duration": "0s",
    "checks": []
  }
}
```

## Expected Result

- `status: observed`
- backend profile list
- scheduler adapter list
- artifact root path
