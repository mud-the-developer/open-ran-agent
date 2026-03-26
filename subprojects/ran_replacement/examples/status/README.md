# RAN Replacement Status Fixtures

This directory holds deterministic mock `ranctl` status responses for the
replacement track.

The fixtures are aligned to the current replacement status schema and keep the
scope fixed to `n79 / real RU / real UE / real Open5GS`.

Fixture set:

- [precheck-target-host-open5gs-n79.status.json](precheck-target-host-open5gs-n79.status.json)
- [verify-attach-ping-open5gs-n79.status.json](verify-attach-ping-open5gs-n79.status.json)
- [observe-failed-ru-sync-open5gs-n79.status.json](observe-failed-ru-sync-open5gs-n79.status.json)
- [observe-registration-rejected-open5gs-n79.status.json](observe-registration-rejected-open5gs-n79.status.json)
- [observe-failed-cutover-open5gs-n79.status.json](observe-failed-cutover-open5gs-n79.status.json)
- [rollback-gnb-cutover-open5gs-n79.status.json](rollback-gnb-cutover-open5gs-n79.status.json)
- [capture-artifacts-failed-cutover-open5gs-n79.status.json](capture-artifacts-failed-cutover-open5gs-n79.status.json)
- [capture-artifacts-registration-rejected-open5gs-n79.status.json](capture-artifacts-registration-rejected-open5gs-n79.status.json)

Use these as mock dashboard and runner responses only. They are sanitized and
intended to match the replacement track's `precheck`, `verify`, `observe`,
`rollback`, and `capture-artifacts` control shapes, including explicit
`failure_class` and `ngap_subset` metadata for the declared subset.
