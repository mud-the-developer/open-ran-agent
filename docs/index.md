---
layout: home

hero:
  name: Open RAN Agent
  text: Design-first Open RAN docs and operator workflows
  tagline: Architecture, ADRs, production-facing control and evidence workflows, and static docs for the current support posture.
  image:
    src: /assets/logo/open-ran-agent-32.svg
    alt: Open RAN Agent logo
  actions:
    - theme: brand
      text: Start with architecture
      link: /architecture/
    - theme: alt
      text: Read ADRs
      link: /adr/
    - theme: alt
      text: Review backlog
      link: /backlog/

features:
  - title: Architecture-first
    details: "System boundaries, failure domains, southbound contracts, and operational semantics are documented before runtime expansion."
  - title: Evidence-first ops
    details: "ranctl, Deploy Studio, remote handoff, and debug packs all converge on deterministic artifacts and explicit evidence."
  - title: Pages-ready docs
    details: "This docs tree builds into a static site that can be previewed locally and deployed through a simple Git-integrated Pages flow."
---

<div class="doc-kicker">Documentation Hub</div>

The site groups the repo into three operator-friendly surfaces:

- **Architecture** for boundaries, contracts, target-host workflows, and support posture
- **ADRs** for the decisions that lock those boundaries in place
- **Backlog** for the next implementation cuts

<div class="docs-hero-grid">
  <a class="docs-hero-card" href="/architecture/00-system-overview">
    <img src="/assets/figures/architecture-overview.svg" alt="Architecture overview figure">
    <strong>System shape</strong>
    <span>Start with the BEAM, native boundary, deploy surface, and evidence flow in one pass.</span>
  </a>
  <a class="docs-hero-card" href="/architecture/05-ranctl-action-model">
    <img src="/assets/figures/ranctl-lifecycle.svg" alt="ranctl lifecycle figure">
    <strong>Control lifecycle</strong>
    <span>Understand how precheck, plan, apply, verify, rollback, and capture-artifacts hang together.</span>
  </a>
  <a class="docs-hero-card" href="/architecture/12-target-host-deployment">
    <img src="/assets/figures/target-host-deploy.svg" alt="Target-host deployment figure">
    <strong>Deploy loop</strong>
    <span>See the handoff, preflight, remote execution, and fetchback path for real hosts.</span>
  </a>
  <a class="docs-hero-card" href="/architecture/15-production-control-evidence-and-interoperability-lanes">
    <img src="/assets/figures/ranctl-lifecycle.svg" alt="Support posture figure">
    <strong>Support posture</strong>
    <span>See the evidence-backed runtime lanes, their proof surfaces, and the future expansion lanes that still need proof.</span>
  </a>
</div>

## Fast paths

<div class="doc-hub-grid">
  <a class="doc-hub-card" href="/architecture/">
    <strong>Architecture guide</strong>
    <span>System overview, supervision layout, failure domains, southbound contracts, runtime bridge, deploy workflow, and debug runbooks.</span>
  </a>
  <a class="doc-hub-card" href="/adr/">
    <strong>ADRs</strong>
    <span>Read the accepted decisions that define the repo's build structure, boundary choices, and operational model.</span>
  </a>
  <a class="doc-hub-card" href="/backlog/">
    <strong>Backlog</strong>
    <span>See the current implementation queue and the future runtime-expansion lanes that still need proof.</span>
  </a>
</div>

## What is here today

- design-first architecture docs for the RAN control and ops stack
- production-facing control, deploy, evidence, and recovery workflows through `ranctl`, Deploy Studio, and target-host tooling
- explicit support-posture documentation for hardened-now versus future-lane claims
- a static documentation site that can be deployed without adding a backend

<div class="doc-callout">
  This site is intentionally documentation-centric. It explains the current
  operator control, evidence, and bounded runtime support posture, and it keeps
  future expansion lanes explicit until they are proven.
</div>
