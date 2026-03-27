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

## Evidence-backed Runtime Lanes

These lanes are current support claims with repo-visible proof:

| Lane | Current support | Explicit non-claim |
| --- | --- | --- |
| `Declared live protocol lane` | `n79_single_ru_single_ue_lab_v1` has real target-host lifecycle, attach, registration, session, ping, and rollback evidence | no multi-cell, multi-DU, or broad profile parity claim |
| `Aerial clean-room runtime` | `aerial_fapi_profile` supports `aerial_clean_room_runtime_v1` through shared Port runtime, strict host probes, and gateway lifecycle proof | no vendor device bring-up proof, no attach-plus-ping proof on Aerial, no production timing claim |
| `cuMAC clean-room scheduler` | `cumac_scheduler` supports `cumac_scheduler_clean_room_runtime_v1` through executable slot plans, explicit CPU rollback target metadata, and cell-group-scoped ownership | no external scheduler worker proof, no attach validation claim, no production timing claim |

## Later

These remain future expansion lanes:

- multi-cell and multi-DU orchestration
- handover support
- advanced scheduling coordination beyond one cell-group lane
- real DU-low implementation
- vendor-backed NVIDIA Aerial integration
- external-worker cuMAC scheduler integration
- live SCTP, NGAP, F1AP, E1AP, and GTP-U integration beyond the declared `n79` lane

## Out Of Scope For This Bootstrap

- production timing guarantees
- PHY or low-PHY implementation
- vendor-specific Aerial internals
- distributed control plane clustering decisions
