# Replacement Packages

This directory holds implementation-facing boundary packages for the RAN replacement track.

Rules:
- Keep this layer docs/contracts-first.
- Keep runtime code out of these packages until the contract is explicit.
- Do not place slot-paced logic, FAPI hot-path logic, or any RT loop behavior here.
- Treat each package as a narrow boundary around one protocol or control surface.

## Milestone-1 Ownership Freeze

| Package | Runtime owner(s) | Cutover owner | Rollback owner | Package non-goal |
| --- | --- | --- | --- | --- |
| `ngap_edge` | `ran_cu_cp` owns NGAP-facing control/session state; the real `Open5GS` core remains the external peer runtime for registration state. | `ran_action_gateway` via `bin/ranctl` once the NGAP and target-host gates are explicit. | `ran_action_gateway` via `bin/ranctl`, with `ran_cu_cp` surfacing `UE Context Release` cleanup evidence back to the named rollback target. | No RU timing, scheduler behavior, or user-plane forwarding logic. |
| `f1e1_control_edge` | `ran_cu_cp` owns the primary `F1-C` and `E1AP` coordination surface, with `ran_cu_up` and `ran_du_high` as explicit peer runtimes. | `ran_action_gateway` via `bin/ranctl` after control-plane association and config gates are explicit. | `ran_action_gateway` via `bin/ranctl`, with `ran_cu_cp`, `ran_cu_up`, and `ran_du_high` restoring a clean association state. | No slot-paced logic, PHY code, or hidden shell-script control path. |
| `user_plane_edge` | `ran_cu_up` owns tunnel/session lifecycle, `ran_du_high` owns DU-local forwarding orchestration, and native contract gateways own timing-sensitive forwarding beneath the package boundary. | `ran_action_gateway` via `bin/ranctl` after control-plane and target-host gates prove the forwarding lane is ready. | `ran_action_gateway` via `bin/ranctl`, with `ran_cu_up`, `ran_du_high`, and the native gateway clearing or restoring forwarding state. | No hot-path forwarding implementation, no full `GTP-U` parity promise, and no direct core replacement logic. |
| `target_host_edge` | `ran_config` and `ran_action_gateway` own the repo-visible host-readiness contract; the external target host remains the live owner of NIC, kernel, timing, and install state. | `ran_action_gateway` via `bin/ranctl` precheck/plan/apply gating. | `ran_action_gateway` via `bin/ranctl`, returning the lane to the last approved deploy/profile state when readiness regresses. | No live packet handling, no hidden host secrets, and no protocol implementation. |
| `core_link_edge` | `ran_cu_cp` owns N2-facing control state, `ran_cu_up` owns N3/session tunnel state, and the real `Open5GS` core remains the external owner of subscriber/core session state. | `ran_action_gateway` via `bin/ranctl` once the named core profile, NGAP, and user-plane gates are explicit. | `ran_action_gateway` via `bin/ranctl`, with `ran_cu_cp` and `ran_cu_up` restoring the replacement-side state while preserving explicit core-link evidence. | No core implementation replacement, no hidden Open5GS-specific runtime code, and no radio timing logic. |

Current package families:
- `ngap_edge`: NGAP-facing control boundary for core attachment, registration, and session setup flows.
- `f1e1_control_edge`: F1-C and E1AP control boundary for CU-CP, CU-UP, and DU coordination.
- `user_plane_edge`: F1-U and GTP-U boundary for the declared user-plane forwarding path.
- `target_host_edge`: host readiness and preflight boundary for the real lab deployment lane.
- `core_link_edge`: real Open5GS core-link boundary for NGAP and session-level interop.

Expected contents for each package:
- `README.md` describing intended contract, runtime owner(s), cutover owner, rollback owner, and non-goals.
- `CONTRACT.md` describing boundary inputs, outputs, explicit rollback ownership, and contract rules before any implementation work.
- Minimal examples or fixtures only when they clarify the boundary.
