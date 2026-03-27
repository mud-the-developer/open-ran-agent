# Topology-Scale Claim Lanes

Status: draft

## Goal

Decompose broader topology expansion into separately reviewable future lanes so
the repo can talk about multi-cell, multi-DU, multi-UE, and mobility work
without turning the current single-lane proof into an accidental broad-support
claim.

`YON-60` bounded broader profile expansion as one roadmap lane. `YON-66`
replaces that single umbrella with explicit topology-scope profiles that are
profile-defined and testable, but still not runtime-proven.

## Baseline That Must Stay Intact

The current supported replacement lane remains:

- `n79_single_ru_single_ue_lab_v1`
- one DU
- one cell group
- one real UE
- one real `Open5GS` core
- one attach-plus-ping path

Nothing in this note widens that claim. The single-lane profile remains the
only bounded runtime target profile in the repo today.

## Topology-Scope Profile Rules

Every topology-scale future lane must ship as a schema-backed profile fixture
under `contracts/topology-scope-profile-v1.schema.json`.

Every such profile must define:

- the exact topology shape and counts
- the blast radius and isolated failure domains
- the approval scope and required reviewer checks
- the rollback target, rollback triggers, and rollback evidence reference
- the evidence artifacts and success criteria
- the repo-visible validation commands or tests that pin the profile
- explicit non-claims so the repo cannot imply broader runtime support

## Future Lanes Defined In This Repo

### `n79_multi_cell_single_du_lab_v1`

Purpose:

- define a two-cell, one-DU future lane without implying broad multi-cell
  parity

Guardrails:

- blast radius is capped to the declared cell pair on one DU
- approval must call out shared-DU saturation and per-cell rollback visibility
- rollback must be able to restore either cell without widening past the
  declared DU
- evidence must stay per-cell and per-DU

### `n79_multi_du_single_ue_lab_v1`

Purpose:

- define a two-DU future lane without implying generalized distributed-DU
  support

Guardrails:

- blast radius is capped to the declared DU pair and their named cells
- approval must call out DU ownership, transport assumptions, and cutover order
- rollback must restore the prior DU assignment and transport state
- evidence must keep DU-local state transitions reviewable

### `n79_multi_ue_single_du_lab_v1`

Purpose:

- define a bounded multi-UE lane without implying generalized throughput or
  scheduler scaling claims

Guardrails:

- blast radius is capped to the declared UE cohort on one DU and one cell
- approval must call out scheduler saturation and subscriber isolation checks
- rollback must restore the single-UE baseline or fully remove the extra UE
  state
- evidence must keep UE-by-UE attach, session, and ping outcomes reviewable

### `n79_mobility_handover_lab_v1`

Purpose:

- define a bounded mobility lane for one declared UE handover path

Guardrails:

- blast radius is capped to the named source and target cells or DUs
- approval must call out handover sequencing, source-target readiness, and path
  switch checks
- rollback must restore the pre-handover serving path or leave a cleanly
  auditable blocked state
- evidence must preserve pre-handover, handover, path-switch, and post-handover
  verification artifacts

## Reviewer Rules

- Treat the topology-scope profiles as future-lane contracts, not current
  runtime support claims.
- Treat `profile_defined_not_runtime_proven` as a hard non-claim of live
  support.
- Do not promote the single-lane profile into multi-cell, multi-DU, multi-UE,
  or mobility language unless the matching topology-scope profile has explicit
  repo-visible validation and evidence.
- If a new topology family appears later, add another topology-scope profile
  instead of mutating the current single-lane target profile.
