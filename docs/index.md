---
layout: home

hero:
  name: Open RAN Agent
  text: Control-plane docs for Open RAN operators
  tagline: Architecture map, ranctl action path, target-host rollout, and failure evidence for the bootstrap stack.
  image:
    src: /assets/logo/open-ran-agent-32.svg
    alt: Open RAN Agent logo
  actions:
    - theme: brand
      text: Open architecture
      link: /architecture/
    - theme: alt
      text: Read change flow
      link: /architecture/05-ranctl-action-model
    - theme: alt
      text: Target-host deploy
      link: /architecture/12-target-host-deployment
---

<div class="doc-kicker">Operator Guide</div>

<section class="landing-band">
  <div class="landing-band-copy">
    <p class="landing-band-label">Scope summary</p>
    <h2>Read owner, flow, and evidence before touching runtime details.</h2>
    <p>
      This site is the working index for the repo. It is written for engineers who need quick
      answers to three questions: who owns the boundary, how does the change run, and where do
      artifacts land when the run fails.
    </p>
  </div>
  <div class="landing-band-list">
    <div class="landing-band-item">
      <strong>Current scope</strong>
      <span>1 DU / 1 cell / attach to ping target</span>
    </div>
    <div class="landing-band-item">
      <strong>Mutation gate</strong>
      <span><code>bin/ranctl</code> with approval on destructive paths</span>
    </div>
    <div class="landing-band-item">
      <strong>Deploy loop</strong>
      <span>preview -> preflight -> remote ranctl -> fetchback</span>
    </div>
    <div class="landing-band-item">
      <strong>Evidence set</strong>
      <span>plan, verify, capture, debug pack, remote run</span>
    </div>
  </div>
</section>

<section class="landing-split">
  <article class="landing-panel landing-panel-xl">
    <div class="landing-panel-head">
      <span class="landing-chip">Primary diagram</span>
      <h2>Start with the full ownership map before drilling into any single lane.</h2>
      <p>
        This is the shortest path to the current control model: BEAM ownership, native
        southbound boundary, runtime bridge, and evidence outputs.
      </p>
    </div>
    <a class="landing-figure-card" href="/architecture/00-system-overview">
      <img src="/assets/figures/architecture-overview.svg" alt="Architecture overview figure">
    </a>
  </article>

  <aside class="landing-rail">
    <a class="landing-rail-card" href="/architecture/05-ranctl-action-model">
      <span class="landing-rail-label">Change path</span>
      <strong>Follow precheck, plan, apply, verify, rollback, and capture-artifacts.</strong>
      <img src="/assets/figures/ranctl-lifecycle.svg" alt="ranctl lifecycle figure">
    </a>
    <a class="landing-rail-card" href="/architecture/12-target-host-deployment">
      <span class="landing-rail-label">Target-host path</span>
      <strong>See handoff, preflight, remote execution, and evidence fetchback in one loop.</strong>
      <img src="/assets/figures/target-host-deploy.svg" alt="Target-host deployment figure">
    </a>
  </aside>
</section>

## Jump by job

<div class="doc-hub-grid doc-hub-grid-wide">
  <a class="doc-hub-card doc-hub-card-accent" href="/architecture/">
    <span class="doc-hub-overline">Architecture</span>
    <strong>Architecture guide</strong>
    <span>System overview, supervision layout, failure domains, southbound contracts, runtime bridge, deploy path, and debug workflow.</span>
  </a>
  <a class="doc-hub-card" href="/adr/">
    <span class="doc-hub-overline">Decision record</span>
    <strong>ADRs</strong>
    <span>Accepted decisions for umbrella layout, BEAM-native split, canonical IR, ranctl mutation model, and Open5GS-facing compatibility.</span>
  </a>
  <a class="doc-hub-card" href="/backlog/">
    <span class="doc-hub-overline">Implementation queue</span>
    <strong>Backlog</strong>
    <span>The remaining work toward real transports, target-host validation, and runtime hardening.</span>
  </a>
  <article class="doc-hub-card doc-hub-card-stack">
    <span class="doc-hub-overline">Working tools</span>
    <strong>Primary operator surfaces</strong>
    <ul class="doc-inline-list">
      <li><code>bin/ranctl</code> for deterministic mutation</li>
      <li><code>bin/ran-dashboard</code> for local observability</li>
      <li><code>bin/ran-install</code> for target-host handoff</li>
      <li><code>bin/ran-debug-latest</code> for shortest failure-to-evidence path</li>
    </ul>
  </article>
</div>

## What this documentation is strongest at today

<section class="landing-columns">
  <article class="landing-column-card">
    <span class="landing-chip">Strongest</span>
    <h3>Boundaries and operator semantics</h3>
    <p>
      The documentation is strongest where the repo is strongest: boundary ownership,
      failure domains, deterministic control flow, deploy preview, target-host preflight,
      and evidence collection.
    </p>
  </article>
  <article class="landing-column-card">
    <span class="landing-chip landing-chip-warm">Deferred on purpose</span>
    <h3>Production runtime internals</h3>
    <p>
      Real DU-low, Aerial internals, production timing guarantees, and complete live stack
      behavior remain explicitly staged. The docs are honest about those edges rather than
      disguising them as finished.
    </p>
  </article>
</section>

<section class="landing-timeline">
  <div class="landing-timeline-head">
    <p class="landing-band-label">Suggested read order</p>
    <h2>Read top down once, then return only to the lane you own.</h2>
  </div>
  <ol class="landing-timeline-list">
    <li>
      <strong><a href="/architecture/00-system-overview">00. System overview</a></strong>
      <span>Understand the repo's target shape, MVP boundary, and what remains deferred.</span>
    </li>
    <li>
      <strong><a href="/architecture/05-ranctl-action-model">05. ranctl action model</a></strong>
      <span>See the single mutable action path and why every rollback-capable flow routes through it.</span>
    </li>
    <li>
      <strong><a href="/architecture/09-oai-du-runtime-bridge">09. OAI DU runtime bridge</a></strong>
      <span>Bridge architecture into a real executable runtime path without pretending the BEAM owns RT loops.</span>
    </li>
    <li>
      <strong><a href="/architecture/12-target-host-deployment">12. target-host deployment</a></strong>
      <span>Follow ship, preflight, remote ranctl, and fetchback for actual hosts.</span>
    </li>
    <li>
      <strong><a href="/architecture/14-debug-and-evidence-workflow">14. debug and evidence workflow</a></strong>
      <span>Keep the shortest path from operator failure to artifacts, transcripts, and snapshots.</span>
    </li>
  </ol>
</section>

<div class="doc-callout doc-callout-strong">
  The target style here is an internal telecom runbook, not a product landing page. If it scans well under pressure, it is doing the right job.
</div>
