# User Plane Edge Package

This package defines the F1-U and GTP-U boundary for the replacement track.

Intended contract:
- Express the user-plane edge that carries the declared UE traffic between CU-UP, DU, and the real core path.
- Cover tunnel establishment, TEID association, forwarding state, and ping-relevant user-plane evidence.
- Stay aligned with the standards subset and procedure matrices before any implementation work starts.

Non-goals:
- No slot-paced logic.
- No FAPI hot-path logic.
- No RT scheduler behavior.
- No PHY or RU timing code.
- No direct Open5GS integration code in this directory until the contract is fixed.

Boundary rule:
- Keep this package as a docs/contracts-first shell until the F1-U and GTP-U contract, schema, and examples are explicit.
- Any future implementation here should remain thin and should only adapt the established contract.

References:
- `subprojects/ran_replacement/notes/08-f1-u-and-gtpu-standards-subset.md`
- `subprojects/ran_replacement/notes/11-f1-u-and-gtpu-procedure-support-matrix.md`
- `subprojects/ran_replacement/notes/12-standards-evidence-and-acceptance-gates.md`
- `subprojects/ran_replacement/notes/13-milestone-1-acceptance-runbook.md`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-request-v1.schema.json`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-status-v1.schema.json`
