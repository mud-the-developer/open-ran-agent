# CI and Release Bootstrap

## Intent

Bootstrap the repo with a single repeatable quality gate before introducing heavier packaging or deployment logic.

## Current contract

- local validation now has two layers:
  - `mix contract_ci`: format, compile, and tests excluding runtime-tagged smoke paths
  - `mix runtime_ci`: runtime-tagged smoke tests plus bootstrap bundle generation
- `mix ci` runs both layers in order
- GitHub Actions mirrors the same split in `.github/workflows/ci.yml`
- CI now also publishes bootstrap artifacts:
  - contract job: architecture and ADR docs snapshot
  - runtime job: `artifacts/releases/ci-smoke/**`, runtime evidence, and capture JSONs when present

## Why this shape

- the repo is still architecture-first and placeholder-heavy
- some flows are heavier than basic contract checks:
  - mocked OAI runtime orchestration
  - bundle packaging smoke
- the split keeps the default gate readable while preserving a place for runtime-adjacent regression checks

## Release stance today

- `bin/ranctl` and `bin/ran-dashboard` remain the operator-facing bootstrap entrypoints
- both scripts still compile the umbrella on demand and run directly from the checked-out repo
- the first distributable unit is now a `bootstrap_source_bundle` built by `mix ran.package_bootstrap`
- this bundle is intentionally source-first:
  - entrypoints: `bin/ranctl`, `bin/ran-dashboard`
  - source tree: `apps/`, `bin/`, `config/`, `docs/`, `examples/`, `native/`, `ops/`
  - manifest: `artifacts/releases/<bundle_id>/manifest.json`
  - tarball: `artifacts/releases/<bundle_id>/open_ran_agent-<bundle_id>.tar.gz`
  - host installer helper: `artifacts/releases/<bundle_id>/install_bundle.sh`

The bundle now also carries a target-host preflight path through:

- `bin/ran-host-preflight`
- `ops/deploy/preflight.sh`
- `ops/deploy/systemd/*.service`

## Release-time sanity checks

`mix ran.package_bootstrap` rejects topologies that are not ready for controlled failover packaging.

Current checks:

- base config validation must pass
- each `cell_group` must declare at least one `failover_target`
- `failover_targets` must be unique
- `failover_targets` must not include the current backend

This is stricter than generic bootstrap validation because the package is meant to carry an operator-ready failover contract, not only a runnable checkout.

## Next release-oriented tasks

- decide whether a compiled BEAM release or operator container image supersedes the source bundle
- add artifact publishing for docs, captures, and release bundles in CI once a distribution registry is chosen
