---
layout: home

hero:
  name: Open RAN Agent
  text: Design-first Open RAN docs and operator workflows
  tagline: Architecture, ADRs, target-host deployment, evidence loops, and Cloudflare-hosted documentation for the bootstrap repo.
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
      text: Deploy this site
      link: /cloudflare-pages

features:
  - title: Architecture-first
    details: "System boundaries, failure domains, southbound contracts, and operational semantics are documented before runtime expansion."
  - title: Evidence-first ops
    details: "ranctl, Deploy Studio, remote handoff, and debug packs all converge on deterministic artifacts and explicit evidence."
  - title: Pages-ready docs
    details: "This docs tree builds into a static site that can be previewed locally and deployed directly to Cloudflare Pages."
---

<div class="doc-kicker">Documentation Hub</div>

The site groups the repo into three operator-friendly surfaces:

- **Architecture** for boundaries, contracts, and target-host workflows
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
    <span>See the current implementation queue and how the bootstrap still needs to move toward real runtime and transport integration.</span>
  </a>
  <a class="doc-hub-card" href="/cloudflare-pages">
    <strong>Cloudflare Pages</strong>
    <span>Use the built-in VitePress and Wrangler setup to build, preview, and deploy this docs site as a static Pages project.</span>
  </a>
</div>

## What is here today

- design-first architecture docs for the RAN control and ops stack
- executable bootstrap surfaces such as `ranctl`, Deploy Studio, and target-host preflight
- operator-oriented deployment and evidence workflows
- a static documentation site that can be deployed without adding a backend

<div class="doc-callout">
  This site is intentionally documentation-centric. It explains the current bootstrap honestly, including what is working today and what still remains synthetic or deferred.
</div>
