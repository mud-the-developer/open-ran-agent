# OAI CU/DU Replacement Task Plan

Last updated: 2026-03-25  
Status: active design, target-profile definition, and control-surface planning

## Mission

Build a clean-room replacement track for the operator-visible role currently filled by `OAI NR CU/DU`, while preserving the repository's operating model and interoperating with a real `Open5GS`-based core:

- no agent logic in slot-paced or RT-sensitive paths
- no mutable actions outside `bin/ranctl`
- explicit approval for destructive actions and cutovers
- explicit rollback targets
- BEAM control logic, native RT workers, and ops workflows kept separate
- compatibility defined by real `n79` lab behavior, not vague "similar enough" claims
- replacement defined by owning the target-profile `OAI`-visible `CU/DU` function chain
- standards-correct behavior required at the declared external interfaces for the supported scope
- explicit ownership across `S`, `M`, `C`, and `U` plane concerns

The first real target is:

- one `n79` deployment
- one real RU
- one real UE
- one real `Open5GS` core
- one `attach + ping` success path

## End-State Definition

This effort is only considered successful when all of the following hold for the declared target profile:

1. A replacement-track `gNB` stack can own the `CU-CP`, `CU-UP`, and `DU` operator lifecycle without relying on OAI runtime ownership for the declared cutover lane.
2. The system interoperates with a real `Open5GS`-based core over the declared target-profile interfaces.
3. The system can complete a real-lab `UE attach + ping` path on `n79`.
4. The RU link is real, not `RFsim`.
5. The target host passes deterministic preflight and runtime verify checks before cutover is allowed.
6. `S`, `M`, `C`, and `U` plane responsibilities are explicit and evidenced for the target profile.
7. All mutable lifecycle steps are reachable through `bin/ranctl` and agent-friendly CLI façades.
8. Each risky action emits deterministic evidence:
   - `precheck`
   - `plan`
   - `apply`
   - `verify`
   - `rollback_plan`
   - `capture-artifacts`
9. The replacement lane has an explicit rollback target.
10. The replacement path remains honest about what is still delegated to native workers, external datapaths, or upstream interoperability harnesses.
11. The replacement lane owns the target-profile `OAI`-visible function chain required for cell bring-up, access, registration, PDU session establishment, and ping.
12. The declared external interfaces are standards-correct for the supported procedure subset and target profile.

## Non-Negotiable Constraints

- Do not place agent or LLM logic inside scheduler, slot, FAPI, RU, or other RT-sensitive loops.
- Do not bypass `bin/ranctl` for mutating control actions.
- Do not copy OpenAirInterface implementation code into committed files.
- Keep any future upstream checkout under `subprojects/ran_replacement/upstream/` and ignored.
- Do not commit private RU configs, SIM data, UE configs, secret IP plans, or lab captures.
- Do not hide real-core assumptions in local-only notes; the `Open5GS` dependency must be written down explicitly.
- Update ADRs or architecture docs before changing repo-level boundaries.
- Mark stubs with TODOs and state the intended future contract.

## Source Of Truth Inside This Repo

- `subprojects/ran_replacement/README.md`
- `subprojects/ran_replacement/AGENTS.md`
- `subprojects/ran_replacement/task.md`
- `docs/architecture/00-system-overview.md`
- `docs/architecture/04-du-high-southbound-contract.md`
- `docs/architecture/05-ranctl-action-model.md`
- `docs/architecture/07-mvp-scope-and-roadmap.md`
- `docs/architecture/08-open-questions-and-risks.md`
- `docs/architecture/09-oai-du-runtime-bridge.md`
- `docs/architecture/12-target-host-deployment.md`
- `docs/adr/0002-beam-vs-native-boundary.md`
- `docs/adr/0004-ranctl-as-single-action-entrypoint.md`
- `docs/adr/0007-ran-functions-as-agent-friendly-cli-surface.md`
- `docs/adr/0008-oai-cu-du-function-and-standards-baseline.md`
- `subprojects/ran_replacement/notes/04-open5gs-core-and-s-m-c-u-plane-scope.md`
- `subprojects/ran_replacement/notes/05-oai-function-and-standards-baseline.md`

## Current Code Touchpoints

These are the first repo locations that a replacement track would have to integrate with before any live runtime cutover:

- `bin/ranctl`
- `bin/ran-dashboard`
- `bin/ran-install`
- `apps/ran_action_gateway/lib/ran_action_gateway/request.ex`
- `apps/ran_action_gateway/lib/ran_action_gateway/change.ex`
- `apps/ran_action_gateway/lib/ran_action_gateway/runner.ex`
- `apps/ran_action_gateway/lib/ran_action_gateway/oai_runtime.ex`
- `apps/ran_action_gateway/lib/ran_action_gateway/store.ex`
- `apps/ran_config/lib/ran_config/topology_loader.ex`
- `apps/ran_config/lib/ran_config/validator.ex`
- `apps/ran_config/lib/ran_config/change_policy.ex`
- `apps/ran_observability/lib/ran_observability/dashboard/snapshot.ex`
- `apps/ran_observability/lib/ran_observability/dashboard/action_runner.ex`
- `apps/ran_observability/priv/dashboard/assets/dashboard.js`
- `apps/ran_du_high/`
- `apps/ran_fapi_core/`
- `native/local_du_low_adapter/`
- `native/fapi_rt_gateway/`
- `examples/ranctl/`

## Key Non-Obvious Findings

- The repo already has a deterministic operator lifecycle. A replacement track should reuse it instead of inventing a second mutable control path.
- The real approval gate lives in `apps/ran_action_gateway/lib/ran_action_gateway/runner.ex`, not in a thin CLI wrapper.
- The hardest blocker for a real `n79` lane may be host timing, fronthaul, RU sync, UE lab quality, and real `Open5GS` N2/N3 interoperability rather than CU/DU application code by itself.
- "Replacement" must mean a declared lab profile with explicit acceptance, not an open-ended claim of general parity.
- The current dashboard and request builders are mostly `cell_group` oriented; they will need explicit `gNB`, `cell`, `RU`, `RU link`, and `UE session` scopes for this track.
- OAI config import is a useful bootstrap input, but the long-term control surface must move to repo-owned topology and request contracts.
- The replacement lane now assumes a real external core, so registration, PDU session, and ping evidence must be first-class acceptance artifacts.
- A replacement milestone must be evaluated on actual function ownership and standards behavior, not on orchestration polish alone.

## Replacement Scope For Milestone 1

Milestone 1 is intentionally narrow:

- `n79` only
- one lab profile only
- one real target host only
- one RU type only
- one UE class only
- one real `Open5GS` core profile only
- one attach-plus-ping path only
- no multi-cell orchestration
- no handover
- no claim of broad feature parity outside the target profile

But milestone 1 is still strict within that narrow scope:

- the required `CU/DU` function chain must actually be owned
- the declared external interfaces must be standards-correct for the supported subset

## Phase 0: Lock The Exact Target Profile

Goal:
Freeze the real lab profile before implementation spreads.

Tasks:
- [ ] Define the canonical target profile name, for example `n79_single_ru_single_ue_lab_v1`.
- [ ] Define the exact target-profile function chain that must be owned without depending on OAI runtime ownership.
- [ ] Pin the RF profile:
  - band
  - bandwidth
  - numerology
  - SCS
  - TDD pattern
  - antenna count
- [ ] Pin the RU boundary:
  - transport type
  - fronthaul mode
  - sync source
  - timing dependencies
  - NIC or PCI ownership
- [ ] Pin the UE boundary:
  - device class
  - SIM and core assumptions
  - logging and observability path
- [ ] Pin the real core boundary:
  - `Open5GS` release or profile
  - N2 bind and routing assumptions
  - N3 and user-plane assumptions
  - subscriber and DNN assumptions
  - evidence path for registration and session setup
- [ ] Pin the host assumptions:
  - OS
  - kernel
  - hugepages
  - PTP or GPS source
  - NIC timestamping
- [ ] Write success criteria for:
  - RU sync
  - SSB visibility
  - RACH success
  - RRC setup
  - registration against real `Open5GS`
  - PDU session against real `Open5GS`
  - ping through the declared user-plane path
- [ ] Name the minimum standards-correct interface subset for milestone 1:
  - `NGAP`
  - `F1-C`
  - `F1-U`
  - `E1AP`
  - `GTP-U`

Deliverables:
- target-profile note under `subprojects/ran_replacement/notes/`
- lab acceptance checklist
- target-host preflight checklist

DoD:
- Nobody can say "replacement is working" without naming this exact profile.

## Phase 1: Define The Agent-Friendly CLI Surface

Goal:
Expose RAN functions in a way that agents, humans, dashboard flows, and remote runners can all drive consistently.

Tasks:
- [ ] Define resource scopes for replacement-track control:
  - `gnb`
  - `cu_cp`
  - `cu_up`
  - `du`
  - `cell`
  - `ru`
  - `ru_link`
  - `ue_session`
  - `transport_profile`
  - `target_host`
  - `core_link`
- [ ] Define read-only actions:
  - `get`
  - `list`
  - `observe`
  - `verify`
- [ ] Define reversible actions:
  - `drain`
  - `resume`
  - `freeze-attaches`
  - `unfreeze-attaches`
  - `reload-config`
  - `capture-artifacts`
- [ ] Define destructive or cutover actions:
  - `bring-up`
  - `tear-down`
  - `switch-runtime`
  - `cutover`
  - `rollback`
- [ ] Define stable output for every CLI path:
  - `status`
  - `checks`
  - `approval_required`
  - `rollback_available`
  - `artifacts`
  - `suggested_next`
- [ ] Map short human-facing commands to canonical JSON requests.
- [ ] Keep hot-path internals outside per-slot CLI semantics.

Deliverables:
- CLI taxonomy note
- request and status contract draft
- example commands and example JSON requests

DoD:
- Agent control does not require ad hoc shell scripts or bespoke one-off wrappers.

## Phase 2: Extend Topology And Config For Replacement Scope

Goal:
Model replacement-track inventory in repo-owned config instead of hiding it in opaque metadata.

Tasks:
- [ ] Extend topology shape for:
  - gNB identity
  - CU/DU ownership
  - cell profile
  - RU inventory
  - RU link and timing dependencies
  - target-host inventory
  - fallback runtime target
- [ ] Add explicit `target_profile` and `compatibility_profile` fields.
- [ ] Add explicit `core_profile`, `n2_profile`, and `n3_profile` fields.
- [ ] Add config validation for:
  - missing RU link
  - missing timing source
  - missing rollback target
  - missing real-core routing assumptions
  - mismatched band or bandwidth assumptions
- [ ] Add import rules for upstream OAI-like configs without making them the long-term source of truth.
- [ ] Add sanitized example topology for the `n79` milestone profile.

Deliverables:
- topology note
- additive config contract
- validation checklist

DoD:
- A replacement-track target can be described and validated without private lab files in git.

## Phase 3: Freeze Protocol And Runtime Boundaries

Goal:
Make it explicit what the replacement track owns, what remains native, and what remains external.

Tasks:
- [ ] Write boundary notes for:
  - `F1-C`
  - `F1-U`
  - `E1AP`
  - `NGAP`
  - `GTP-U`
  - RU/fronthaul boundary
  - timing and sync boundary
- [ ] Write explicit ownership notes for:
  - `S-plane`
  - `M-plane`
  - `C-plane`
  - `U-plane`
- [ ] Define which functions remain BEAM-side and which remain native-side.
- [ ] Define what counts as a public compatibility contract for `CU/DU`.
- [ ] Define what is owned by the replacement lane versus the real `Open5GS` core.
- [ ] Define what remains out of scope for milestone 1.
- [ ] Define what evidence is needed at each boundary during verify.
- [ ] Define the supported standards procedure subset for each declared interface in milestone 1.

Deliverables:
- boundary note set
- interface contract drafts

DoD:
- There is no ambiguity about whether a given function belongs in BEAM, native, or external infrastructure.

## Phase 4: Make ranctl Understand Replacement Scopes

Goal:
Express replacement-track lifecycle through the existing deterministic operator model.

Tasks:
- [ ] Extend request parsing for new scopes and actions.
- [ ] Extend change modeling for gNB, RU, and target-host aware operations.
- [ ] Add precheck paths for:
  - RU readiness
  - timing readiness
  - target-host readiness
  - rollback target presence
- [ ] Add plan output that names:
  - affected resource
  - expected interfaces
  - expected artifacts
  - approval requirements
  - rollback path
- [ ] Keep early apply paths explicit about which runtime edges are still stubs.
- [ ] Add example payloads under `subprojects/ran_replacement/examples/ranctl/`.

Deliverables:
- request and runner design extension
- example requests
- early contract tests

DoD:
- Replacement-track actions have the same deterministic control shape as current repo actions.

## Phase 5: Add Dashboard And Evidence Awareness

Goal:
Make replacement-track actions observable without bespoke tooling.

Tasks:
- [ ] Extend dashboard snapshot for:
  - gNB state
  - RU link state
  - target-host readiness
  - UE session outcome
  - attach and ping evidence
- [ ] Add artifact kinds for:
  - RU sync reports
  - timing and PTP checks
  - attach evidence
  - ping evidence
  - replacement compare reports
- [ ] Extend Deploy Studio and remote-run views for replacement scopes.
- [ ] Add operator-facing debug summaries for failed attach and failed RU sync.

Deliverables:
- snapshot and evidence model
- replacement artifact taxonomy

DoD:
- A failed run can be understood from dashboard plus artifacts without SSH archaeology as the first step.

## Phase 6: Target-Host And Lab Readiness

Goal:
Treat the real host and real lab as first-class dependencies, not last-minute details.

Tasks:
- [ ] Define host preflight checks for:
  - NIC presence
  - PTP state
  - hugepages
  - PCI inventory
  - fronthaul or RU link resources
  - CPU isolation and IRQ expectations
- [ ] Define RU readiness checks for:
  - sync
  - reachable control surface
  - expected timing health
- [ ] Define UE readiness checks for:
  - SIM and subscriber assumptions
  - band support
  - logging or debug path
- [ ] Extend deploy preview and readiness scoring for replacement scope.
- [ ] Define "blocked", "degraded", and "ready_for_preflight" semantics for the real-lab lane.

Deliverables:
- preflight contract
- readiness scoring contract
- real-lab checklist

DoD:
- The system can fail early and honestly before a risky cutover begins.

## Phase 7: Replacement Milestones By Function Family

Goal:
Avoid all-at-once cutover by replacing one responsibility lane at a time.

Tasks:
- [ ] Define `shadow`, `observe-only`, `cutover-candidate`, and `active` states for each family:
  - `cu_cp`
  - `cu_up`
  - `du_high`
  - `du_low_or_native_rt`
- [ ] Define what comparison evidence is needed before each family can cut over.
- [ ] Define rollback target for each family.
- [ ] Decide which family goes first and why.
- [ ] Define transition rules so mixed ownership remains explicit rather than accidental.

Deliverables:
- staged cutover matrix
- family-specific rollback rules

DoD:
- Replacement can progress incrementally without losing operator visibility.

## Phase 8: Native RT Replacement Plan

Goal:
Make the hardest real-time edges explicit instead of letting them hide under "later".

Tasks:
- [ ] Define DU-low and southbound ownership goals for the target profile.
- [ ] Define native worker expectations for:
  - queue model
  - timing window
  - host probe
  - handshake
  - health
  - restart and drain behavior
- [ ] Define the minimum runtime behavior needed to support the milestone 1 attach-plus-ping path.
- [ ] Define what remains external even after milestone 1.

Deliverables:
- native RT milestone note
- worker contract note

DoD:
- The most timing-sensitive ownership boundaries are explicit before implementation begins.

## Phase 9: n79 End-To-End Acceptance

Goal:
Define the real final proof for milestone 1.

Tasks:
- [ ] Write an executable runbook for:
  - host preflight
  - RU readiness
  - gNB bring-up
  - F1/E1/NG path verification
  - UE registration against real `Open5GS`
  - PDU session against real `Open5GS`
  - ping through the live user-plane path
- [ ] Define acceptance evidence:
  - RU sync state
  - protocol health markers
  - attach evidence
  - registration and PDU session evidence
  - ping result
  - rollback evidence
- [ ] Define soak expectations:
  - minimum runtime
  - acceptable error budget
  - acceptable restart count
- [ ] Define failure classes and first debug artifacts to inspect.

Deliverables:
- acceptance runbook
- milestone 1 evidence bundle checklist

DoD:
- "Works" means one real RU, one real UE, `n79`, attach, and ping, with captured evidence.

## Phase 10: Explicit Non-Goals Until Milestone 1 Lands

These stay out of scope until milestone 1 is complete:

- multi-band support
- multi-RU or multi-cell orchestration
- handover
- generalized performance tuning beyond the target lab
- broad parity claims outside the declared target profile
- hidden ad hoc agent or shell control paths

## Immediate Next Contracts And Fixtures To Deepen

1. Tighten `contracts/ranctl-ran-replacement-request-v1.schema.json` per scope instead of leaving additive draft flexibility.
2. Tighten `contracts/ranctl-ran-replacement-status-v1.schema.json` with scope-specific evidence fields for RU, registration, and ping.
3. Add a `n79-single-ru-target-profile-v1.schema.json` once the real lab owner freezes exact RF and RU assumptions.
4. Add sanitized `observe` and `capture-artifacts` examples for failed RU sync and failed registration.
5. Add interface-specific standards baseline notes for `NGAP`, `F1-C`, `F1-U`, `E1AP`, and `GTP-U`.
