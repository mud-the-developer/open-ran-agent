# MVP Scope And Roadmap

## MVP Now

- one node or tightly scoped lab deployment
- one DU-high runtime
- one cell group
- one UE attach plus ping path
- canonical IR and backend profile selection
- `stub_fapi_profile`, `local_fapi_profile`, and `aerial_fapi_profile` contract paths
- `ranctl` command contract and approval model
- observability and artifact capture skeleton

## Next

- push the local DU-low Port path from synthetic sidecar toward a real native worker
- add config validation and release packaging
- add integration tests for drain, switch, verify, and rollback
- model backend health and degraded states more concretely
- deepen the `cumac_scheduler` contract host toward a real external scheduler worker
- keep the core AMF SCTP edge bounded and explicit while it moves from flat JSON intent to a bounded NGAP-shaped JSON envelope for `NGSetup`, `InitialUEMessage`, `UplinkNASTransport`, `DownlinkNASTransport`, `PDUSessionResourceSetup`, and `UEContextRelease`
- keep the core SMF and UPF-control PFCP edge bounded and explicit while it covers the implemented Create*/Modification subset and bounded Remove* grouped-IE handling before any broader PFCP parity claim
- keep `subprojects/ran_replacement/` as a separate design-first track for an `OAI CU/DU` replacement targeting one `n79` real-RU and real-UE attach-plus-ping lane against a real `Open5GS` core, with an agent-friendly `ranctl` control surface before runtime cutover

## Later

These items are roadmap-only interoperability lanes. They are not current
support claims:

- multi-cell and multi-DU orchestration
- handover support
- advanced scheduling coordination
- real DU-low implementation
- real NVIDIA Aerial adapter
- real cuMAC scheduler adapter
- live SCTP, NGAP, F1AP, E1AP, and GTP-U integration

For roadmap review, treat them as separate future lanes:

| Lane | Hardened-now support | Explicit non-claim | Tracking issue |
| --- | --- | --- | --- |
| `Aerial interoperability` | `aerial_fapi_profile` contract scaffolding, shared Port bootstrap runtime, session lifecycle scaffolds, and host-probe gating | no vendor device bring-up proof, no attach-plus-ping proof, no production timing claim | `YON-58` |
| `cuMAC scheduler interoperability` | `ran_scheduler_host` boundary plus placeholder `cumac_scheduler` adapter surface | no external scheduler worker proof, no runtime timing proof, no attach validation claim | `YON-59` |
| `broader profile expansion` | one DU, one cell group, one UE bootstrap lane plus contract-only backend surfaces | no multi-cell parity claim, no multi-DU parity claim, no broad vendor/profile parity claim | `YON-60` |

## Out Of Scope For This Bootstrap

- production timing guarantees
- PHY or low-PHY implementation
- vendor-specific Aerial internals
- distributed control plane clustering decisions
