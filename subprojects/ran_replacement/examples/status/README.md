# RAN Replacement Status Fixtures

This directory holds deterministic mock `ranctl` status responses for the
replacement track.

The fixtures are aligned to the current replacement status schema and keep the
scope fixed to `n79 / real RU / real UE / real Open5GS`.

Fixture set:

- [precheck-target-host-open5gs-n79.status.json](precheck-target-host-open5gs-n79.status.json)
- [verify-attach-ping-open5gs-n79.status.json](verify-attach-ping-open5gs-n79.status.json)
- [observe-failed-ru-sync-open5gs-n79.status.json](observe-failed-ru-sync-open5gs-n79.status.json)
- [observe-failed-cutover-open5gs-n79.status.json](observe-failed-cutover-open5gs-n79.status.json)
- [rollback-gnb-cutover-open5gs-n79.status.json](rollback-gnb-cutover-open5gs-n79.status.json)
- [capture-artifacts-failed-cutover-open5gs-n79.status.json](capture-artifacts-failed-cutover-open5gs-n79.status.json)
- [capture-artifacts-registration-rejected-open5gs-n79.status.json](capture-artifacts-registration-rejected-open5gs-n79.status.json)

Use these as mock dashboard and runner responses only. They are sanitized and
intended to match the replacement track's `precheck`, `verify`, `observe`,
`rollback`, and `capture-artifacts` control shapes.

## Claim Boundaries

These fixtures are allowed to claim only the milestone-1 NGAP subset that the
replacement track has made explicit.

### Required procedure claims

The repo-visible status fixtures may show:

- `NG Setup`
- `Initial UE Message`
- `Uplink NAS Transport`
- `Downlink NAS Transport`
- `UE Context Release`

These are the only NGAP procedures that may appear as attach-path progress in
the current fixtures.

### Optional recovery claims

The fixtures may also show evidence about optional recovery-oriented behavior:

- `Error Indication`
- `Reset`

These are not attach-path success criteria. If they appear, they must remain
diagnostic or recovery-only.

### Deferred procedure claims

The fixtures must not imply active support for deferred milestone-1 procedures:

- `Paging`
- `Handover Preparation`
- `Path Switch Request`

If later milestones bring these procedures into scope, this README and the
replacement example smoke tests must be updated in the same patch.
