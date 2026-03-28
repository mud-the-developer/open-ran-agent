# NGAP Procedure Support Matrix

Status: draft

## Scope

This note records the milestone-1 NGAP subset for the `n79` replacement track.
The baseline assumption is a real external `Open5GS` core, a real RU, and a real UE.

The matrix is intentionally small.
It is meant to tell the team which NGAP procedures are required for milestone 1,
which are bounded supported claims beyond the happy-path gate, and which are
deferred until after the initial attach + ping path is proven.

## Matrix

| Procedure | Purpose | Milestone-1 status | Evidence | Rollback relevance |
| --- | --- | --- | --- | --- |
| `NG Setup` | Establish the NG control-plane connection to the real `Open5GS` core and confirm the node can register itself as an NG peer. | required | `precheck`, `plan`, `verify`, and captured NG setup logs or status entries that name the real core endpoint. | High. If NG setup fails, rollback or fallback is the first safe recovery path. |
| `Initial UE Message` | Carry the first UE-originated NAS signaling into the NG control plane during attach. | required | UE attach trace, NGAP procedure trace, and evidence that the real core saw the access attempt. | High. A failure here usually means the attach lane should stop and clean up. |
| `Uplink NAS Transport` | Deliver UE-originated NAS payloads toward the real `Open5GS` core. | required | NAS transport trace plus the attach evidence bundle. | High. Rollback should release any partially established UE context. |
| `Downlink NAS Transport` | Deliver core-originated NAS payloads back toward the UE during registration and session setup. | required | Core-side registration evidence plus downlink NAS trace in the capture bundle. | High. If the core rejects or stalls here, the path should be reverted and the release state recorded. |
| `UE Context Release` | Cleanly release UE state after success, failure, abort, or rollback. | required | Release trace, cleanup logs, and post-action evidence that the UE context is gone. | High. This is the main cleanup procedure for abort and rollback paths. |
| `Paging` | Wake a UE that is not actively signaling. | deferred | None in milestone 1 unless a later acceptance case requires it. | Low. Not needed for the initial attach + ping path. |
| `Handover Preparation` | Transfer UE control between access nodes. | deferred | None in milestone 1. | Low. Outside the initial single-cell attach scope. |
| `Path Switch Request` | Move user-plane anchoring after mobility events. | deferred | None in milestone 1. | Low. Only matters once handover is in scope. |
| `Error Indication` | Report recoverable NG control-plane errors to the peer. | supported | Error traces and compare or rollback evidence must keep the procedure explicit when this bounded support claim is cited. | Medium. Useful for diagnosis and bounded recovery review, but not a success criterion. |
| `Reset` | Force a broad control-plane state reset. | supported | Reset intent, peer-state recovery, and rollback evidence must stay explicit when this claim is used. | High. It remains a bounded escape hatch, not part of the happy path. |

## Interpretation Rules

- `required` means milestone 1 is not complete without the procedure working in the declared attach + ping flow.
- `supported` means the repo now makes a bounded, reviewable support claim for the procedure, but milestone 1 must not depend on it as a happy-path pass gate.
- `deferred` means it is out of scope for milestone 1 and should not be counted as attach-path progress.

## Evidence Rules

Evidence should stay aligned with the replacement track contract surface:

- `precheck` should explain whether the declared NGAP subset is reachable.
- `plan` should state the target profile, the real `Open5GS` core endpoint, and the rollback target.
- `verify` should show the last observed NGAP procedure and whether registration progressed.
- `capture-artifacts` should preserve the attach trace, cleanup trace, and any rollback evidence.
- compare-report and rollback surfaces should keep any claimed `Error Indication` or `Reset` behavior explicit when those procedures explain the safer operator action.

## Rollback Rule

The rollback target for milestone 1 is the last safe state before the attach attempt or before the current cutover step.
If a required NGAP procedure fails, the evidence must show:

- which procedure failed
- whether the failure was access, transport, or core rejection
- whether `UE Context Release` completed
- whether control returned to the declared rollback target
