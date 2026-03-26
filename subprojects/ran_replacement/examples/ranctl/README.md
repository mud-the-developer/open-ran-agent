# RAN Replacement ranctl Examples

This directory will hold sanitized example payloads for the replacement track.

Expected first examples:

- target-host precheck
- RU readiness observe
- gNB bring-up plan
- attach freeze and unfreeze
- replacement cutover plan
- rollback after failed attach evidence

Runbook alignment:

- keep the examples aligned with `notes/12-standards-evidence-and-acceptance-gates.md`
- use `notes/13-milestone-1-acceptance-runbook.md` as the operator sequence reference
- keep all example payloads sanitized and profile-specific

Operator workflow rule:

- every live-lab precheck, verify, and rollback payload should stay traceable to
  the first failed layer, the rollback target, and the next artifact an
  operator should inspect

Current draft files:

- [precheck-target-host-open5gs-n79.json](precheck-target-host-open5gs-n79.json)
- [plan-gnb-bringup-open5gs-n79.json](plan-gnb-bringup-open5gs-n79.json)
- [verify-attach-ping-open5gs-n79.json](verify-attach-ping-open5gs-n79.json)
- [rollback-gnb-cutover-open5gs-n79.json](rollback-gnb-cutover-open5gs-n79.json)
- [observe-failed-ru-sync-open5gs-n79.json](observe-failed-ru-sync-open5gs-n79.json)
- [capture-artifacts-failed-ru-sync-open5gs-n79.json](capture-artifacts-failed-ru-sync-open5gs-n79.json)
- [observe-registration-rejected-open5gs-n79.json](observe-registration-rejected-open5gs-n79.json)
- [capture-artifacts-registration-rejected-open5gs-n79.json](capture-artifacts-registration-rejected-open5gs-n79.json)
- [observe-ping-failed-open5gs-n79.json](observe-ping-failed-open5gs-n79.json)
- [capture-artifacts-ping-failed-open5gs-n79.json](capture-artifacts-ping-failed-open5gs-n79.json)
- [observe-failed-cutover-open5gs-n79.json](observe-failed-cutover-open5gs-n79.json)
- [capture-artifacts-failed-cutover-open5gs-n79.json](capture-artifacts-failed-cutover-open5gs-n79.json)

Use only sanitized topology and metadata here.
