# Dashboard Fixture Mapping

Status: draft

## Goal

Describe how the replacement-track fixtures should surface in the dashboard so
operators can move between mission cards, inspector views, and remote-run
summaries without guessing which file or artifact to inspect next.

This note is intentionally dashboard-facing rather than runtime-facing. It
maps sanitized fixture families to the UI surfaces that should explain them.

## Fixture Families

The replacement track currently needs two fixture families to stay readable in
the dashboard:

- `examples/status/*.status.json`
- `examples/artifacts/*.json`

The first family is the canonical mock response surface for `ranctl` status
commands. The second family is the canonical evidence surface for compare
reports, rollback evidence, debug packs, and remote-run summaries.

If a fixture cannot be named in one of these families, the dashboard should not
pretend it is first-class evidence.

## Mission Card Mapping

Mission cards should answer one question quickly: "what is the lane trying to
prove right now?"

### `precheck-target-host-open5gs-n79.status.json`

Mission card:

- target host readiness
- RU timing readiness
- Open5GS core route readiness

Expected card fields:

- `gate_class`
- `target_profile`
- `core_profile`
- `ru_status`
- `core_link_status`
- `rollback_available`

### `verify-attach-ping-open5gs-n79.status.json`

Mission card:

- milestone-1 attach-plus-ping proof

Expected card fields:

- `gate_class`
- `attach_status`
- `pdu_session_status`
- `ping_status`
- `interface_status.ngap`
- `interface_status.f1_c`
- `interface_status.e1ap`
- `interface_status.f1_u`
- `interface_status.gtpu`

### `observe-*.status.json`

Mission card:

- failed RU sync
- failed registration
- failed ping
- failed cutover

Expected card fields:

- `gate_class`
- `summary`
- `checks`
- `suggested_next`
- `rollback_target`

## Inspector View Mapping

Inspector views should answer: "what evidence explains this state?"

### Status fixtures

Status fixtures should populate the inspector with:

- the latest gate class
- per-plane status
- per-interface status
- attach, PDU session, and ping substatus
- rollback availability

For failure cases, the inspector should point to the first blocked interface
and the first artifact path that a human should open next.

### Artifact fixtures

Artifact fixtures should populate the inspector with:

- compare reports
- rollback evidence
- debug pack summaries
- remote-run transcripts
- capture bundles

The inspector should not flatten these into a generic blob. It should keep the
artifact family visible so the operator can tell whether the run failed in
`precheck`, `verify`, `observe`, `rollback`, or `capture-artifacts`.

## Remote-Run Summary Mapping

Remote-run summaries should be the compact operator view of a completed or
failed action.

They should always surface:

- `target_host`
- `target_profile`
- `change_id`
- `incident_id`
- `command`
- `status`
- `gate_class`
- `rollback_target`
- `artifacts`
- `suggested_next`

For the replacement track, the summary should also expose whether the run was
about:

- RU readiness
- registration
- PDU session
- ping
- rollback after failed cutover

The summary should also say whether the run is being presented as:

- standards-subset evidence
- compatibility-baseline evidence
- a combined live-lab acceptance dossier

## Dashboard Rules

The dashboard should follow these rules when rendering replacement fixtures:

- status fixtures drive the mission cards
- artifact fixtures drive the inspector and remote-run summary views
- compare reports and rollback evidence should be linked, not merged
- failed runs should show the first failed interface before the final summary
- `rollback_target` should always be visible when the lane is mutable
- live-lab acceptance dossiers should keep operator-facing summaries separate
  from raw artifact blobs

## Non-Goals

This note does not define runtime behavior.

It does not replace the standards evidence note or the milestone-1 acceptance
runbook. It only says how the dashboard should map the existing fixture families
into operator-readable surfaces.
