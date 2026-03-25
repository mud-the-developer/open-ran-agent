# RAN Replacement Incident Examples

This directory holds sanitized incident notes for the replacement track.

The first four examples cover the failure modes that matter most in a strict
`n79 / real RU / real UE / real Open5GS` lane:

- [Failed RU sync before attach](failed-ru-sync-before-attach.md)
- [Registration rejected by real Open5GS](registration-rejected-by-real-open5gs.md)
- [PDU session established but ping failed](pdu-session-established-but-ping-failed.md)
- [Rollback after failed cutover](rollback-after-failed-cutover.md)

Each incident note should stay operator-friendly and point to:

- the request payload used for the run
- the evidence artifact or verify output that failed
- the first debug pack or capture artifact to inspect
- the rollback decision and outcome
