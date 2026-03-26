# RAN Replacement Contracts

This directory holds draft contracts for the replacement track's control and
evidence surface.

These schemas are part of the current hardened-now review posture: they make
status, compare reports, rollback evidence, and target-profile assumptions
explicit and schema-backed.

They do not, by themselves, claim supported live runtime cutover, `Aerial`
runtime ownership, `cuMAC` scheduler ownership, or broader interoperability
beyond the declared `n79` plus real `Open5GS` lane.

For broader profile expansion specifically, the current contract posture stays
fixed to the single declared lane:

- one `n79` profile
- one real RU
- one real UE
- one real `Open5GS` core

These contracts do not yet claim:

- multi-cell parity
- multi-DU parity
- broad RU/core/vendor/profile parity outside that declared lane

Current schema set:

- `ranctl-ran-replacement-request-v1.schema.json`
- `ranctl-ran-replacement-status-v1.schema.json`
- `n79-single-ru-target-profile-v1.schema.json`
- `n79-single-ru-target-profile-overlay-v1.schema.json`
- `compare-report-v1.schema.json`
- `rollback-evidence-v1.schema.json`
- `open5gs-core-link-profile-v1.schema.json`

The immediate rule is simple:

- define contracts before runtime ownership expands
- keep the contracts additive to the existing `ranctl` model
- do not hide runtime-only assumptions in unversioned notes

## Compatibility Fields

The target-profile and lab-overlay contracts now carry explicit compatibility
metadata:

- `compatibility_surface` in the canonical target profile example
- `compatibility_alignment` in the lab-owner overlay example

These fields name:

- the compatibility profile
- the required NF set
- the required I/O surfaces
- the operator-facing surfaces or declared deviations tied to that profile

Current draft files:

- [ranctl-ran-replacement-request-v1.schema.json](ranctl-ran-replacement-request-v1.schema.json)
- [ranctl-ran-replacement-status-v1.schema.json](ranctl-ran-replacement-status-v1.schema.json)
- [n79-single-ru-target-profile-v1.schema.json](n79-single-ru-target-profile-v1.schema.json)
- [n79-single-ru-target-profile-overlay-v1.schema.json](n79-single-ru-target-profile-overlay-v1.schema.json)
- [examples/n79-single-ru-target-profile-v1.example.json](examples/n79-single-ru-target-profile-v1.example.json)
- [examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json](examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json)
- [compare-report-v1.schema.json](compare-report-v1.schema.json)
- [rollback-evidence-v1.schema.json](rollback-evidence-v1.schema.json)
- [open5gs-core-link-profile-v1.schema.json](open5gs-core-link-profile-v1.schema.json)
