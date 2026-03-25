# Failed RU Sync Before Attach

## Symptom

The replacement lane gets through host preflight and initial plan generation,
but the RU never reaches a stable sync state. The run stops before any useful
UE attach attempt should be trusted.

Typical operator-facing signs:

- `precheck` reports RU readiness as blocked or degraded
- `verify` never reaches a confident attach-ready state
- the dashboard shows the RU link as unhealthy or missing timing confidence

## Likely Gate or Check Failure

The usual failure is a readiness gate, not a late runtime bug:

- missing RU link or wrong transport assumptions
- missing timing source or unstable PTP/GPS lock
- mismatched band, bandwidth, or TDD assumptions
- RU control surface reachable, but sync health not acceptable

## Expected Request Payload References

- [precheck-target-host-open5gs-n79.json](../ranctl/precheck-target-host-open5gs-n79.json)
- [plan-gnb-bringup-open5gs-n79.json](../ranctl/plan-gnb-bringup-open5gs-n79.json)

## Expected Artifacts and Evidence

- RU sync report
- host preflight report
- readiness score and blocker list
- `capture-artifacts` bundle for the failed lane

## First Debug Steps

1. Inspect the host timing and RU link assumptions first.
2. Check whether the RU transport and sync source match the declared target profile.
3. Compare the readiness blockers against the active request payload.
4. Confirm the failure is not a stale artifact from a previous cutover attempt.

## Rollback Decision

Rollback is appropriate if the lane cannot reach a deterministic sync state
after the declared preflight checks. Do not proceed to attach or session
validation until RU sync is stable.
