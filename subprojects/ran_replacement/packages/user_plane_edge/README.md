# User Plane Edge Package

This package defines the F1-U and GTP-U boundary for the replacement track.

Intended contract:
- Express the user-plane edge that carries the declared UE traffic between CU-UP, DU, and the real core path.
- Cover tunnel establishment, TEID association, forwarding state, and ping-relevant user-plane evidence.
- Stay aligned with the standards subset and procedure matrices before any implementation work starts.

## Vocabulary Boundaries

Repo-visible package docs, fixtures, and tests must use one user-plane
standards-subset vocabulary.

### Required vocabulary

The current milestone may positively claim:

- `F1-U` forwarding path
- `GTP-U` tunnel and `TEID` association
- session-to-tunnel association for the declared UE session
- ping proof on the declared route

### Deferred or out-of-scope vocabulary

The package must not imply support for broader user-plane behaviors such as:

- mobility or handover-driven tunnel changes
- roaming or multi-UE session orchestration
- advanced traffic shaping or QoS feature parity

If later milestones expand the subset, update this README and the replacement
example smoke test in the same patch.

## Ownership Freeze

- Runtime owner(s): `ran_cu_up` owns tunnel and session lifecycle state. `ran_du_high` owns DU-local forwarding orchestration. Native contract gateways own the timing-sensitive forwarding and drain/resume behavior beneath the package boundary.
- Cutover owner: `ran_action_gateway` via `bin/ranctl` owns user-plane cutover sequencing once the target-host and control-plane gates are explicit.
- Rollback owner: `ran_action_gateway` via `bin/ranctl` owns rollback orchestration. `ran_cu_up`, `ran_du_high`, and the active native gateway must expose enough state to restore or clear the forwarding path cleanly.

Non-goals:
- No slot-paced logic.
- No FAPI hot-path logic.
- No RT scheduler behavior.
- No PHY or RU timing code.
- No direct Open5GS integration code in this directory until the contract is fixed.

Boundary rule:
- Keep this package as a docs/contracts-first shell until the F1-U and GTP-U contract, schema, and examples are explicit.
- Any future implementation here should remain thin and should only adapt the established contract.

Package-local contract and fixtures:
- [CONTRACT.md](CONTRACT.md)

References:
- `subprojects/ran_replacement/notes/08-f1-u-and-gtpu-standards-subset.md`
- `subprojects/ran_replacement/notes/11-f1-u-and-gtpu-procedure-support-matrix.md`
- `subprojects/ran_replacement/notes/12-standards-evidence-and-acceptance-gates.md`
- `subprojects/ran_replacement/notes/13-milestone-1-acceptance-runbook.md`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-request-v1.schema.json`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-status-v1.schema.json`
