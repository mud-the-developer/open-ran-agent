# F1E1 Control Edge Package

This package defines the F1-C and E1AP control boundary for the replacement track.

Intended contract:
- Express the control-plane edge that coordinates CU-CP, CU-UP, and DU behavior for the declared `n79` target profile.
- Cover setup, config exchange, cell control, UE context setup and release, and safe re-establishment flows.
- Stay aligned with the standards subset and procedure matrices before any implementation work starts.

## Ownership Freeze

- Runtime owner(s): `ran_cu_cp` owns the primary `F1-C` and `E1AP` coordination surface. `ran_cu_up` and `ran_du_high` are explicit peer runtimes for CU-UP and DU state.
- Cutover owner: `ran_action_gateway` via `bin/ranctl` owns cutover sequencing for control-plane association changes.
- Rollback owner: `ran_action_gateway` via `bin/ranctl` owns rollback orchestration. `ran_cu_cp`, `ran_cu_up`, and `ran_du_high` must expose the release and cleanup state needed to prove a clean rollback.

Non-goals:
- No slot-paced logic.
- No FAPI hot-path logic.
- No RT scheduler behavior.
- No PHY or RU timing code.
- No direct Open5GS integration code in this directory until the contract is fixed.

Boundary rule:
- Keep this package as a docs/contracts-first shell until the F1-C and E1AP contract, schema, and examples are explicit.
- Any future implementation here should remain thin and should only adapt the established contract.

Package-local contract and fixtures:
- [CONTRACT.md](CONTRACT.md)
- [examples/observe-failed-cutover.request.json](examples/observe-failed-cutover.request.json)
- [examples/observe-failed-cutover.status.json](examples/observe-failed-cutover.status.json)

References:
- `subprojects/ran_replacement/notes/07-f1-c-and-e1ap-standards-subset.md`
- `subprojects/ran_replacement/notes/10-f1-c-and-e1ap-procedure-support-matrix.md`
- `subprojects/ran_replacement/notes/12-standards-evidence-and-acceptance-gates.md`
- `subprojects/ran_replacement/notes/13-milestone-1-acceptance-runbook.md`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-request-v1.schema.json`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-status-v1.schema.json`
