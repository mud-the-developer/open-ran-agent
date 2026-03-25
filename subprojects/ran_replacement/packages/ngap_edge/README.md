# NGAP Edge Package

This package defines the NGAP-facing boundary for the replacement track.

Intended contract:
- Express the control-plane edge that talks to the core via NGAP.
- Cover registration, context setup, UE attachment, and session control flows that sit at the boundary.
- Stay aligned with the standards subset documented in the replacement notes before any implementation work starts.

Non-goals:
- No slot-paced logic.
- No FAPI hot-path logic.
- No RT scheduler behavior.
- No PHY/RU timing code.
- No direct Open5GS integration code in this directory until the contract is fixed.

Boundary rule:
- Keep this package as a docs/contracts-first shell until the NGAP contract, schema, and examples are explicit.
- Any future implementation here should remain thin and should only adapt the established contract.

References:
- `subprojects/ran_replacement/notes/06-ngap-and-registration-standards-subset.md`
- `subprojects/ran_replacement/notes/09-ngap-procedure-support-matrix.md`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-request-v1.schema.json`
- `subprojects/ran_replacement/contracts/ranctl-ran-replacement-status-v1.schema.json`
