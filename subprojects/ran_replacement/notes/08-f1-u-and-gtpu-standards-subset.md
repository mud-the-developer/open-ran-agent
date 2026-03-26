# F1-U And GTP-U Standards Subset

Status: draft

## Goal

Define the minimum user-plane behavior the replacement track must own for milestone 1.

The target is narrow:

- one `n79` profile
- one real RU
- one real UE
- one real `Open5GS` core
- one attach-plus-ping path

The point of this note is not broad user-plane parity.
The point is a standards-correct user-plane baseline for the declared lab target.

## Required Path Ownership

The replacement lane must own the path needed for a successful ping after registration and PDU session setup.

That means the lane must own or explicitly mediate:

- `F1-U` user-plane traffic between DU and CU
- `GTP-U` tunnel handling at the declared boundary
- PDU session forwarding needed for the target UE
- the user-plane portion of the attach-plus-ping success path

The real `Open5GS` core remains the external core dependency.
This note only defines the replacement-side user-plane ownership required to interoperate with it.

## Minimal Tunnel And Session Behavior

For milestone 1, the user-plane contract should be limited to the smallest useful set:

- create the tunnel or forwarding state required for the declared UE session
- carry the traffic needed for ping success
- preserve clear association between the UE session and the user-plane path
- expose deterministic health and failure reasons when the path is missing or broken

The replacement track does not need to claim broad GTP-U feature parity in milestone 1.
It does need to be able to move traffic for the one declared lab profile in a standards-correct way.

## Evidence Expectations

Every user-plane milestone 1 run should be able to answer:

- was the user-plane path established
- did the UE session reach the expected forwarding state
- did ping traverse the declared path
- what exact artifact proves it
- what exact artifact explains failure

Useful evidence kinds include:

- session establishment logs
- tunnel or forwarding state snapshots
- ping result
- verify summary
- rollback evidence if cutover fails

## Allowed Temporary Deviations

Temporary deviations are allowed only when they are explicit and bounded.

For milestone 1, allowed deviations include:

- shadow ownership before direct cutover
- a narrow supported procedure subset instead of full GTP-U feature coverage
- external helpers for host timing or transport plumbing that are not part of the user-plane function itself
- lab-specific observability adapters that do not change the on-wire behavior

These deviations are not allowed to hide unsupported behavior.
If the replacement lane depends on a deviation, the deviation must be named in precheck, plan, verify, or incident evidence.

## Non-Goals

This note does not claim:

- full GTP-U feature parity
- multi-UE data-plane scaling
- multi-cell or multi-RU data-plane behavior
- handover
- roaming
- advanced traffic shaping
- production timing guarantees
- vendor-specific internals
- replacing the real `Open5GS` core in this track

The milestone 1 promise is only:

- one real UE
- one real RU
- one real `Open5GS` core
- one `n79` profile
- ping on the declared user-plane path
