# PDU Session Established but Ping Failed

## Symptom

Registration succeeds and the core accepts a PDU session, but user-plane ping
does not complete.

Typical operator-facing signs:

- session setup succeeds in the core
- `verify` shows user-plane establishment, but packet reachability fails
- the user-plane evidence exists, but the end-to-end path is not usable

## Likely Gate or Check Failure

The failure is usually in the user-plane contract or host path:

- `F1-U` or `GTP-U` path mismatch
- N3 routing or tunnel mapping mismatch
- MTU, firewall, or source/destination address mismatch
- UE side route or address assignment issue

## Expected Request Payload References

- [verify-attach-ping-open5gs-n79.json](../ranctl/verify-attach-ping-open5gs-n79.json)
- [plan-gnb-bringup-open5gs-n79.json](../ranctl/plan-gnb-bringup-open5gs-n79.json)

## Expected Artifacts and Evidence

- PDU session establishment evidence
- ping failure evidence
- user-plane path summary
- `capture-artifacts` bundle with `F1-U` and `GTP-U` markers

## First Debug Steps

1. Check whether the user-plane path matches the declared target profile.
2. Confirm the tunnel, interface, and routing assumptions on both sides.
3. Compare the failure with the `F1-U` and `GTP-U` support matrices.
4. Inspect whether the core accepted the session but the host path dropped packets.

## Rollback Decision

Rollback is appropriate if the cutover altered user-plane ownership or if the
failure is tied to a risky switch. If the issue is only a host routing mismatch,
fix the path before re-running the same change.
