# OAI RFsim + UE Sim Dashboard Walkthrough

## Goal

Give reviewers one Pages-backed path through the repo-local OAI simulation lane:

1. bring up the split `CU-CP + CU-UP + DU` RFsim lane
2. refresh the `observe` artifact that feeds the dashboard
3. inspect the `DU/CU Protocol State` surface
4. tie the UI back to the checked-in simulation review bundle and the issue / PR evidence that introduced it

Use this page when a change claims "simulation dashboard proof" and you want to
confirm exactly what was proven.

## Current evidence map

| Surface | Current source | Linked issue / PR evidence | Why it matters |
| --- | --- | --- | --- |
| Repo-local RFsim lifecycle | `mise.toml`, `examples/ranctl/*-oai-du-rfsim-local.json` | [YON-87](https://linear.app/yonsei-ramo/issue/YON-87/m10a-land-repo-local-oai-split-rfsim-bringup-and-operator-facing-run) / [PR #58](https://github.com/mud-the-developer/open-ran-agent/pull/58) | Establishes the repo-local `CU-CP + CU-UP + DU` lane and the `observe` artifact the dashboard reads. |
| Dashboard protocol-state UI and current screenshot | `bin/ran-dashboard`, `/assets/evidence/yon-98-dashboard-protocol-state-tall.png` | [YON-98](https://linear.app/yonsei-ramo/issue/YON-98/m12a-add-ducu-runtime-protocol-state-panels-and-documented-counters-to) / [PR #64](https://github.com/mud-the-developer/open-ran-agent/pull/64) | Shows the operator-facing `DU/CU Protocol State` layout and the documented counter set. |
| Operator-facing proof-surface integration | `docs/architecture/09-oai-du-runtime-bridge.md`, `docs/architecture/14-debug-and-evidence-workflow.md` | [YON-94](https://linear.app/yonsei-ramo/issue/YON-94/milestone-12-parent-turn-the-dashboard-into-an-operator-facing-proof) / [PR #65](https://github.com/mud-the-developer/open-ran-agent/pull/65) | Keeps the dashboard aligned with the repo's operator proof surface instead of a debug-only UI. |
| Refreshed OAI UE-sim media lane | current runtime capture work for the same simulation lane | [YON-101](https://linear.app/yonsei-ramo/issue/YON-101/m12d-run-oai-rfsim-plus-oai-ue-sim-and-capture-dashboard-proof-media) | Tracks the newer operator-facing proof media for this walkthrough when fresh captures land. |

![Dashboard protocol-state panels for the repo-local RFsim lane](/assets/evidence/yon-98-dashboard-protocol-state-tall.png)

Current published screenshot: checked-in dashboard capture from [YON-98](https://linear.app/yonsei-ramo/issue/YON-98/m12a-add-ducu-runtime-protocol-state-panels-and-documented-counters-to) / [PR #64](https://github.com/mud-the-developer/open-ran-agent/pull/64). Use [YON-101](https://linear.app/yonsei-ramo/issue/YON-101/m12d-run-oai-rfsim-plus-oai-ue-sim-and-capture-dashboard-proof-media) to track the refreshed OAI UE-sim media lane when newer captures land.

## Proof Boundary

| Proof tier | Where to inspect | What it proves today | Explicit non-claims |
| --- | --- | --- | --- |
| Simulation proof | this page, [09. OAI DU Runtime Bridge](./09-oai-du-runtime-bridge.md), [14. Debug And Evidence Workflow](./14-debug-and-evidence-workflow.md), `examples/oai/simulation/*.json`, `examples/oai/simulation/review/*` | Repo-local `DU/CU` state from the latest `observe` snapshot plus reviewer-visible attach, registration, session, and ping evidence refs | not real-lab proof, not a real core claim, not RU timing proof, not broader profile parity |
| Bounded standards proof | the dashboard's `Bounded standards lane` panel, [09. OAI DU Runtime Bridge](./09-oai-du-runtime-bridge.md), [15. Production Control, Evidence, And Interoperability Lanes](./15-production-control-evidence-and-interoperability-lanes.md) | Focused `observe` / `verify` protocol evidence for `NGAP`, `F1-C`, `E1AP`, `F1-U`, and attach/session outcomes from the selected bounded-standards run artifact | not a target-host or live-lab claim; do not treat it as broader interoperability proof |
| Real-lab proof | [12. Target Host Deployment](./12-target-host-deployment.md), [15. Production Control, Evidence, And Interoperability Lanes](./15-production-control-evidence-and-interoperability-lanes.md), and the declared live-lane status fixtures under `subprojects/ran_replacement/examples/status/` | Remote-host lifecycle, attach-plus-ping proof, compare reports, and rollback evidence for the declared `n79_single_ru_single_ue_lab_v1` lane | not part of the repo-local RFsim + UE-sim walkthrough; do not infer it from simulation screenshots or review JSON |

## Walkthrough

### 1. Check the exact files that define the lane

The live repo-local dashboard path is driven by:

- `mise run oai-rfsim-lifecycle`
- `bin/ranctl observe --file examples/ranctl/observe-oai-du-rfsim-local.json`
- `bin/ran-dashboard`
- `mise run oai-rfsim-rollback`

The UE-sim review bundle stays checked in under:

- `examples/oai/simulation/attach.json`
- `examples/oai/simulation/registration.json`
- `examples/oai/simulation/session.json`
- `examples/oai/simulation/ping.json`

The reviewer bundle mirrors `verify` / `capture-artifacts` output under:

- `examples/oai/simulation/review/request.json`
- `examples/oai/simulation/review/compare-report.json`
- `examples/oai/simulation/review/rollback-evidence.json`

### 2. Bring the lane up and refresh the dashboard input

```bash
mise run oai-rfsim-lifecycle
bin/ranctl observe --file examples/ranctl/observe-oai-du-rfsim-local.json
```

Run `observe` after the lifecycle command so the dashboard reads the newest
repo-local container state, health fields, and log-token counters rather than a
stale artifact.

### 3. Open the dashboard and inspect the protocol-state surface

```bash
bin/ran-dashboard
```

In the UI:

1. open `DU/CU Protocol State`
2. read the `Repo-local simulation lane` panels first
3. confirm `Service`, `Container state`, `Health`, `Log probe`, and `Log tail lines`
4. use the current screenshot above as the expected layout reference
5. move to the `Bounded standards lane` section only after the simulation lane is clear, so the proof tiers do not get conflated

Treat the current counters as bounded tail indicators, not lifetime totals.
They come from the `observe`-time Docker log tail documented in
[09. OAI DU Runtime Bridge](./09-oai-du-runtime-bridge.md).

### 4. Tie the UI back to the checked-in simulation review artifacts

After the dashboard looks healthy, inspect the checked-in review bundle:

- `examples/oai/simulation/attach.json`
- `examples/oai/simulation/registration.json`
- `examples/oai/simulation/session.json`
- `examples/oai/simulation/ping.json`
- `examples/oai/simulation/review/request.json`
- `examples/oai/simulation/review/compare-report.json`
- `examples/oai/simulation/review/rollback-evidence.json`

The key boundary fields should stay explicit:

- `claim_scope = repo_local_simulation`
- `evidence_tier = simulation`
- `live_lab_claim = false`
- `core_mode = simulated`

If those fields drift, update this page together with
[09. OAI DU Runtime Bridge](./09-oai-du-runtime-bridge.md) and
[15. Production Control, Evidence, And Interoperability Lanes](./15-production-control-evidence-and-interoperability-lanes.md).

### 5. Tie the walkthrough back to issue and PR evidence

Use the issue / PR trail to keep the published page reviewable:

- [YON-87](https://linear.app/yonsei-ramo/issue/YON-87/m10a-land-repo-local-oai-split-rfsim-bringup-and-operator-facing-run) / [PR #58](https://github.com/mud-the-developer/open-ran-agent/pull/58): repo-local split RFsim lifecycle and operator commands
- [YON-98](https://linear.app/yonsei-ramo/issue/YON-98/m12a-add-ducu-runtime-protocol-state-panels-and-documented-counters-to) / [PR #64](https://github.com/mud-the-developer/open-ran-agent/pull/64): protocol-state dashboard panels and the current checked-in screenshot
- [YON-94](https://linear.app/yonsei-ramo/issue/YON-94/milestone-12-parent-turn-the-dashboard-into-an-operator-facing-proof) / [PR #65](https://github.com/mud-the-developer/open-ran-agent/pull/65): operator-facing proof-surface framing
- [YON-101](https://linear.app/yonsei-ramo/issue/YON-101/m12d-run-oai-rfsim-plus-oai-ue-sim-and-capture-dashboard-proof-media): newer OAI UE-sim media capture lane when additional screenshots or artifacts are published

When future tickets refresh the media or the proof boundary, replace the table
above instead of layering untracked references into review comments.

## Maintenance Refresh Checklist

- When the dashboard layout or counters change, replace `/assets/evidence/yon-98-dashboard-protocol-state-tall.png` with the newest checked-in capture and update the evidence map to the latest issue / PR pair.
- When the request filenames or operator commands change, update the command blocks and file lists here together with the OAI runtime bridge doc.
- When the proof boundary changes, update this page together with [09. OAI DU Runtime Bridge](./09-oai-du-runtime-bridge.md) and [15. Production Control, Evidence, And Interoperability Lanes](./15-production-control-evidence-and-interoperability-lanes.md).
- Keep Linear issue links explicit. If the newest media ticket has no PR yet, link the issue and say so directly.
