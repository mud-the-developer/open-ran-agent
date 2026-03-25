# Rollback After Failed Cutover

## Symptom

The replacement lane entered a cutover candidate or active state, but a later
check failed and the operator decided to revert to the previous runtime.

Typical operator-facing signs:

- the cutover changed runtime ownership
- a post-cutover verify failed
- rollback evidence was required before another attempt

## Likely Gate or Check Failure

This is usually not one interface failure but a composite risk decision:

- degraded or unstable runtime health after switch
- missing proof that the new lane owns the expected function chain
- attach or ping regression after cutover
- rollback target not clearly validated before the change

## Expected Request Payload References

- [plan-gnb-bringup-open5gs-n79.json](../ranctl/plan-gnb-bringup-open5gs-n79.json)
- [verify-attach-ping-open5gs-n79.json](../ranctl/verify-attach-ping-open5gs-n79.json)
- [rollback-gnb-cutover-open5gs-n79.json](../ranctl/rollback-gnb-cutover-open5gs-n79.json)

## Expected Artifacts and Evidence

- rollback plan
- rollback execution result
- before/after runtime snapshot
- `capture-artifacts` bundle showing the failed cutover and restore outcome

## First Debug Steps

1. Confirm the rollback target was declared before the cutover.
2. Inspect the failed post-cutover check and its first evidence artifact.
3. Compare the runtime state before and after rollback.
4. Make sure the next attempt uses the corrected request payload, not the same one.

## Rollback Decision

Rollback is the correct decision when the cutover breaks the declared
acceptance path or when the lane cannot prove standards-correct behavior at the
required interface subset. The rollback itself should be evidenced, not implied.
