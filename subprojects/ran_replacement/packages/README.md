# Replacement Packages

This directory holds implementation-facing boundary packages for the RAN replacement track.

Rules:
- Keep this layer docs/contracts-first.
- Keep runtime code out of these packages until the contract is explicit.
- Do not place slot-paced logic, FAPI hot-path logic, or any RT loop behavior here.
- Treat each package as a narrow boundary around one protocol or control surface.

Current package families:
- `ngap_edge`: NGAP-facing control boundary for core attachment, registration, and session setup flows.
- `f1e1_control_edge`: F1-C and E1AP control boundary for CU-CP, CU-UP, and DU coordination.
- `user_plane_edge`: F1-U and GTP-U boundary for the declared user-plane forwarding path.

Expected contents for each package:
- `README.md` describing intended contract, ownership, and non-goals.
- Contract notes and schema references before any implementation work.
- Minimal examples or fixtures only when they clarify the boundary.
