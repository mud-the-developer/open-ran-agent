# Target Host Edge Contract

Status: draft, docs/contracts-first

## Goal

Freeze the host-readiness boundary for the replacement track before any runtime code lands here.

This package owns the declared preflight edge for the milestone-1 lane:

- host inventory and deployment layout checks
- hugepage and kernel expectation checks
- sync and fronthaul resource gating
- explicit blocking or readiness evidence before attach or cutover

It does not own NGAP, F1, E1, GTP-U, or live packet handling.

## Boundary Inputs

Required inputs for this package come from existing replacement-track contracts:

- replacement request contract:
  - `scope = target_host`
  - `metadata.replacement.action = precheck`
  - `metadata.replacement.native_probe` present
- target-profile contract:
  - fixed `n79_single_ru_single_ue_lab_v1` assumptions
- lab-owner overlay:
  - concrete host, RU, and deployment narrowing
- core-link profile:
  - used only to confirm the declared N2/N3 reachability assumptions

## Boundary Outputs

The package must eventually emit enough evidence for operators and agents to answer:

- which host dependency is missing or degraded
- whether timing and fronthaul prerequisites are ready
- whether the declared rollback target is still known
- whether the host is ready for preflight only, or ready for live apply

Expected evidence fields:

- `checks[]` for host, RU sync, and core reachability
- `plane_status.s_plane`, `plane_status.m_plane`, `plane_status.c_plane`, `plane_status.u_plane`
- `ru_status`
- `core_link_status`
- artifact references for host inventory, timing state, RU readiness, and user-plane readiness

## Contract Rules

- Keep this package read-mostly until the explicit preflight contract is stable.
- Keep every package-local fixture schema-backed by the replacement request/status schemas.
- Treat `blocked` as the default when the declared lab requirements are not yet proven.
- Never allow this package to imply live readiness without explicit evidence references.

## Non-Goals

- No slot-paced logic.
- No FAPI hot-path logic.
- No PHY or RU timing implementation code.
- No core protocol implementation code.
- No hidden host-specific secrets or private inventory inside committed fixtures.

## TODO For The First Implementation Pass

- Add a package-local note for readiness score derivation and gating thresholds.
- Add a package-local note for inventory redaction and operator-visible host naming.
- Add compare fixtures for `blocked` versus `ready_for_preflight`.
- Keep the future host probe adapter thin and contract-driven.
