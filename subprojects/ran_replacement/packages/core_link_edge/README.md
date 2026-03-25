# Core Link Edge Package

This package defines the real-core link boundary for the replacement track.

Intended contract:
- Express the Open5GS-facing edge for NGAP and session-level interop in the declared `n79` lab profile.
- Cover core attachment, registration, session establishment, subscriber handling, and the control/data path signals needed for ping acceptance.
- Stay aligned with the Open5GS scope notes and the NGAP and procedure matrices before any implementation work starts.

## Ownership Freeze

- Runtime owner(s): `ran_cu_cp` owns replacement-side N2/NGAP control state. `ran_cu_up` owns replacement-side N3 and session tunnel state. The real `Open5GS` core remains the external owner of subscriber and core session state.
- Cutover owner: `ran_action_gateway` via `bin/ranctl` owns any core-link cutover sequencing once the named core profile and interface gates are explicit.
- Rollback owner: `ran_action_gateway` via `bin/ranctl` owns rollback orchestration. `ran_cu_cp` and `ran_cu_up` must expose enough state to restore the replacement-side view of the last safe core-linked state.

Non-goals:
- No slot-paced logic.
- No FAPI hot-path logic.
- No RT scheduler behavior.
- No PHY or RU timing code.
- No direct Open5GS implementation code in this directory until the contract is fixed.

Boundary rule:
- Keep this package as a docs/contracts-first shell until the core-link contract, schema, and examples are explicit.
- Any future implementation here should remain thin and should only adapt the established contract.

Package-local contract and fixtures:
- [CONTRACT.md](CONTRACT.md)

References:
- `subprojects/ran_replacement/notes/04-open5gs-core-and-s-m-c-u-plane-scope.md`
- `subprojects/ran_replacement/notes/06-ngap-and-registration-standards-subset.md`
- `subprojects/ran_replacement/notes/09-ngap-procedure-support-matrix.md`
- `subprojects/ran_replacement/notes/12-standards-evidence-and-acceptance-gates.md`
- `subprojects/ran_replacement/notes/13-milestone-1-acceptance-runbook.md`
- `subprojects/ran_replacement/contracts/open5gs-core-link-profile-v1.schema.json`
- `subprojects/ran_replacement/contracts/n79-single-ru-target-profile-v1.schema.json`
