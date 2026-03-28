# Architecture Guide

<div class="doc-kicker">System Guide</div>

This section is the narrative path through the repo's current architecture. Read it in order if you want the full model, or jump straight to the part you are changing.

<div class="doc-hub-grid">
  <a class="doc-hub-card" href="/architecture/00-system-overview">
    <strong>00. System overview</strong>
    <span>Purpose, MVP goal, system shape, major boundaries, and explicit deferred decisions.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/01-context-and-boundaries">
    <strong>01. Context and boundaries</strong>
    <span>External systems, BEAM versus native rules, and where backend-specific logic must stop.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/02-otp-apps-and-supervision">
    <strong>02. OTP apps and supervision</strong>
    <span>How the umbrella is partitioned and how supervisors are expected to isolate runtime concerns.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/03-failure-domains">
    <strong>03. Failure domains</strong>
    <span>Recovery units and restart boundaries for association, UE state, cell groups, and gateways.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/04-du-high-southbound-contract">
    <strong>04. Southbound contract</strong>
    <span>Canonical IR, health and capability contracts, gateway sessions, and native adapter expectations.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/05-ranctl-action-model">
    <strong>05. ranctl action model</strong>
    <span>The repo's single mutable control surface and how all operator flows are expected to pass through it.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/09-oai-du-runtime-bridge">
    <strong>09. OAI runtime bridge</strong>
    <span>Current Docker Compose-based OAI DU bridge and how runtime evidence is gathered.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/12-target-host-deployment">
    <strong>12. Target-host deployment</strong>
    <span>Install, preflight, remote execution, and evidence fetchback for real lab hosts.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/14-debug-and-evidence-workflow">
    <strong>14. Debug and evidence</strong>
    <span>The shortest operator path from failure to artifacts, summaries, transcripts, and fetched evidence.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/15-production-control-evidence-and-interoperability-lanes">
    <strong>15. Support posture</strong>
    <span>Current control/evidence surfaces, evidence-backed runtime lanes, and future expansion lanes such as vendor-backed Aerial and external cuMAC.</span>
  </a>
  <a class="doc-hub-card" href="/architecture/16-oai-rfsim-ue-sim-dashboard-walkthrough">
    <strong>16. OAI RFsim dashboard walkthrough</strong>
    <span>Reviewer path for the repo-local OAI RFsim + UE sim lane, dashboard proof surface, and linked issue/PR evidence.</span>
  </a>
</div>

## Suggested reading order

1. Start with [00-system-overview](./00-system-overview.md).
2. Continue through [05-ranctl-action-model](./05-ranctl-action-model.md) for the mutable control surface.
3. Read [09-oai-du-runtime-bridge](./09-oai-du-runtime-bridge.md) and [12-target-host-deployment](./12-target-host-deployment.md) if you care about real host rollout.
4. Keep [14-debug-and-evidence-workflow](./14-debug-and-evidence-workflow.md) open when running changes.
5. Use [15-production-control-evidence-and-interoperability-lanes](./15-production-control-evidence-and-interoperability-lanes.md) when you need the current bounded support versus future-expansion boundary.
6. Use [16-oai-rfsim-ue-sim-dashboard-walkthrough](./16-oai-rfsim-ue-sim-dashboard-walkthrough.md) when you need the operator-facing simulation dashboard proof path plus the current issue / PR evidence trail.
