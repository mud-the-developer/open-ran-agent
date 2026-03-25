# ADR Index

<div class="doc-kicker">Decision Record</div>

These ADRs lock in the boundary and tooling decisions that the bootstrap rests on. Read them when you need to understand why the repo chose a particular path, not just what the current code does.

<div class="doc-hub-grid">
  <a class="doc-hub-card" href="/adr/0001-repo-build-structure">
    <strong>0001. Repo build structure</strong>
    <span>Why the umbrella repo is the baseline and where selective Erlang or native code belongs.</span>
  </a>
  <a class="doc-hub-card" href="/adr/0002-beam-vs-native-boundary">
    <strong>0002. BEAM versus native boundary</strong>
    <span>The separation between control/orchestration and timing-sensitive southbound work.</span>
  </a>
  <a class="doc-hub-card" href="/adr/0003-canonical-fapi-ir">
    <strong>0003. Canonical FAPI IR</strong>
    <span>Why the southbound layer is normalized around a shared IR instead of backend-specific flows.</span>
  </a>
  <a class="doc-hub-card" href="/adr/0004-ranctl-as-single-action-entrypoint">
    <strong>0004. ranctl as single action entrypoint</strong>
    <span>The auditability and rollback rationale for forcing all mutations through one surface.</span>
  </a>
  <a class="doc-hub-card" href="/adr/0005-ops-automation-with-skills-not-mcp">
    <strong>0005. Skills, not MCP</strong>
    <span>Why repo-local skills wrap `ranctl` and stay outside hot paths.</span>
  </a>
  <a class="doc-hub-card" href="/adr/0006-open5gs-public-surface-compatibility-baseline">
    <strong>0006. Open5GS public surface compatibility baseline</strong>
    <span>The constraint line for the new Elixir core track under `subprojects/elixir_core/`.</span>
  </a>
</div>

