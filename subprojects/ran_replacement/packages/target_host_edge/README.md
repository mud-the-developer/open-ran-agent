# Target Host Edge Package

This package defines the target-host control boundary for the replacement track.

Intended contract:
- Express the host readiness and preflight surface for the real lab deployment lane.
- Cover hardware, kernel, hugepage, NIC, timing, and environment checks that must pass before a risky cutover or attach path is attempted.
- Stay aligned with the target-host readiness notes and deploy preview contracts before any implementation work starts.

## Ownership Freeze

- Runtime owner(s): `ran_config` and `ran_action_gateway` own the repo-visible host-readiness contract. The external target host remains the live owner of NIC, kernel, timing, and install state.
- Cutover owner: `ran_action_gateway` via `bin/ranctl` owns the readiness gate that decides whether cutover planning or apply is allowed.
- Rollback owner: `ran_action_gateway` via `bin/ranctl` owns the return to the last approved deploy/profile state when readiness regresses or a host-side cutover must be abandoned.

Non-goals:
- No slot-paced logic.
- No FAPI hot-path logic.
- No RT scheduler behavior.
- No PHY or RU timing code.
- No core protocol handling here.

Boundary rule:
- Keep this package as a docs/contracts-first shell until the target-host control contract, schema, and examples are explicit.
- Any future implementation here should stay thin and should only adapt the established contract.

Package-local contract and fixtures:
- [CONTRACT.md](CONTRACT.md)
- [examples/precheck-target-host.request.json](examples/precheck-target-host.request.json)
- [examples/precheck-target-host.status.json](examples/precheck-target-host.status.json)

References:
- `subprojects/ran_replacement/notes/03-target-host-readiness-and-lab-gates.md`
- `subprojects/ran_replacement/notes/12-standards-evidence-and-acceptance-gates.md`
- `subprojects/ran_replacement/notes/13-milestone-1-acceptance-runbook.md`
- `subprojects/ran_replacement/contracts/n79-single-ru-target-profile-v1.schema.json`
- `subprojects/ran_replacement/contracts/n79-single-ru-target-profile-overlay-v1.schema.json`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-request-v1.schema.json`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-status-v1.schema.json`
