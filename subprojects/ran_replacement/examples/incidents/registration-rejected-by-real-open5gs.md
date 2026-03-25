# Registration Rejected by Real Open5GS

## Symptom

The RU sync path is stable enough to attempt attach, but UE registration is
rejected by the real `Open5GS` core.

Typical operator-facing signs:

- `verify` reaches the registration step, then fails
- the core-side logs show rejection, no context setup, or subscriber mismatch
- the dashboard shows an attach failure even though RU sync looked acceptable

## Likely Gate or Check Failure

The failure is usually in the declared core contract:

- N2 routing or binding mismatch
- subscriber or DNN/APN profile mismatch
- wrong PLMN, TAC, or UE profile assumptions
- `NGAP` procedure support incomplete for the target profile

## Expected Request Payload References

- [verify-attach-ping-open5gs-n79.json](../ranctl/verify-attach-ping-open5gs-n79.json)
- [plan-gnb-bringup-open5gs-n79.json](../ranctl/plan-gnb-bringup-open5gs-n79.json)

## Expected Artifacts and Evidence

- registration failure detail from `verify`
- `capture-artifacts` bundle with core-facing evidence
- core-side log reference or sanitized summary
- rollback plan if the attach attempt changed runtime state

## First Debug Steps

1. Check the subscriber, PLMN, TAC, and DNN assumptions first.
2. Confirm the `NGAP` path and core routing are the ones the request declared.
3. Compare the rejection against the procedure support matrix for `NGAP`.
4. If the mismatch is structural, do not retry blindly; fix the profile first.

## Rollback Decision

Rollback is appropriate if registration failure is caused by a cutover choice
or a runtime state change that should be reversed before another attach test.
If the issue is only subscriber data, prefer config correction before rollback.
