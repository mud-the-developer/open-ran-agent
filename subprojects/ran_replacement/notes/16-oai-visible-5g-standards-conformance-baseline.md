# OAI-Visible 5G Standards Conformance Baseline

Status: draft

## Goal

Define the explicit standards-conformance frame for the repo-visible 5G behavior
the replacement track claims to own.

This note is the shared baseline for:

- the real-core public-surface compatibility claim from `ADR 0006`
- the operator-visible `OAI NR CU/DU` function claim from `ADR 0008`
- the per-interface subset and negative-space notes under this directory
- the validated status and compare-report artifacts that must now distinguish
  `milestone_proof` from `standards_subset`

The point is not broad parity.
The point is one reviewable baseline for the declared `n79` real-lab profile.

## Conformance Frame

| Surface | Standards / baseline source | Supported subset refs | Explicit negative space refs | Repo-visible contracts and evidence |
| --- | --- | --- | --- | --- |
| Open5GS public surface | `docs/adr/0006-open5gs-public-surface-compatibility-baseline.md` | `subprojects/ran_replacement/notes/04-open5gs-core-and-s-m-c-u-plane-scope.md` | `ADR 0006` allowed temporary deviations and note `04` external-ownership limits | `subprojects/ran_replacement/contracts/open5gs-core-link-profile-v1.schema.json`, `subprojects/ran_replacement/packages/core_link_edge/CONTRACT.md` |
| OAI-visible CU/DU function chain | `docs/adr/0008-oai-cu-du-function-and-standards-baseline.md` | `subprojects/ran_replacement/notes/05-oai-function-and-standards-baseline.md` | `ADR 0008` allowed temporary deviations and note `05` success/non-success rules | `subprojects/ran_replacement/README.md`, `subprojects/ran_replacement/task.md`, `subprojects/ran_replacement/contracts/n79-single-ru-target-profile-v1.schema.json` |
| `NGAP` | `3GPP TS 38.413` | `subprojects/ran_replacement/notes/06-ngap-and-registration-standards-subset.md`, `subprojects/ran_replacement/notes/09-ngap-procedure-support-matrix.md` | note `06` negative space and note `09` optional / deferred procedures | `subprojects/ran_replacement/packages/ngap_edge/CONTRACT.md`, `subprojects/ran_replacement/examples/status/observe-registration-rejected-open5gs-n79.status.json`, `subprojects/ran_replacement/examples/artifacts/compare-report-registration-rejected-open5gs-n79.json` |
| `F1-C` | `3GPP TS 38.473` | `subprojects/ran_replacement/notes/07-f1-c-and-e1ap-standards-subset.md`, `subprojects/ran_replacement/notes/10-f1-c-and-e1ap-procedure-support-matrix.md` | note `07` negative space and note `10` non-goals | `subprojects/ran_replacement/packages/f1e1_control_edge/CONTRACT.md`, `subprojects/ran_replacement/examples/status/observe-failed-cutover-open5gs-n79.status.json` |
| `E1AP` | `3GPP TS 37.483` | `subprojects/ran_replacement/notes/07-f1-c-and-e1ap-standards-subset.md`, `subprojects/ran_replacement/notes/10-f1-c-and-e1ap-procedure-support-matrix.md` | note `07` negative space and note `10` non-goals | `subprojects/ran_replacement/packages/f1e1_control_edge/CONTRACT.md`, `subprojects/ran_replacement/examples/status/observe-failed-cutover-open5gs-n79.status.json` |
| `F1-U` and `GTP-U` for the declared UE session path | `3GPP TS 38.415` as the declared NG / PDU-session user-plane frame for this repo-owned subset | `subprojects/ran_replacement/notes/08-f1-u-and-gtpu-standards-subset.md`, `subprojects/ran_replacement/notes/11-f1-u-and-gtpu-procedure-support-matrix.md` | note `08` negative space and note `11` explicit non-goals | `subprojects/ran_replacement/packages/user_plane_edge/CONTRACT.md`, `subprojects/ran_replacement/examples/status/verify-attach-ping-open5gs-n79.status.json`, `subprojects/ran_replacement/examples/artifacts/compare-report-ping-failed-open5gs-n79.json` |

## Evidence Tier Rule

Validated status and compare-report artifacts must declare one of these tiers:

- `milestone_proof`: the artifact proves that a declared lab path ran, but it
  does not claim that the repo has met the explicit supported standards subset.
- `standards_subset`: the artifact is judged against this note, the linked ADRs,
  the linked subset notes, and the linked negative-space notes.

The important rule is simple:

- proof without the declared subset is not a conformance claim
- a conformance claim must keep its negative space explicit
- unsupported or deferred procedures must stay visible as unsupported or deferred

## Measurable Next Lanes

1. `NGAP` standards-tightening lane
   - package-local ownership note for `NG Setup` and `UE Context Release`
   - compare fixtures for accepted versus rejected registration paths
   - evidence naming that keeps the last observed NGAP procedure auditable
2. `F1-C / E1AP` standards-tightening lane
   - package-local ownership note for association identity and peer-state boundaries
   - explicit cleanup semantics for partial setup and cutover divergence
   - compare fixtures that separate healthy setup from rollback-required divergence
3. `F1-U / GTP-U` standards-tightening lane
   - package-local ownership note for session-to-tunnel identity
   - explicit forwarding-cleanup semantics for failed cutover
   - compare fixtures that separate ping proof from user-plane subset conformance
4. public-surface compatibility and evidence lane
   - keep `ADR 0006` and `ADR 0008` attached to the repo-visible baseline
   - require conformance-tier metadata in validated evidence artifacts
   - keep failure artifacts explicit about whether the miss is subset-related,
     core-related, or proof-only
