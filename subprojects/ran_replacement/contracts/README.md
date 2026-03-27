# RAN Replacement Contracts

This directory holds draft contracts for the replacement track's control and
evidence surface.

These schemas are part of the current hardened-now review posture: they make
status, compare reports, rollback evidence, and target-profile assumptions
explicit and schema-backed.

They do not, by themselves, claim vendor-backed `Aerial` runtime ownership,
external-worker `cuMAC` scheduler ownership, or broader interoperability beyond
the declared `n79` plus real `Open5GS` lane.

The repo's current clean-room runtime proof for `Aerial` and `cuMAC` lives in
capability metadata, architecture docs, and runtime tests rather than in these
schemas alone.

For the `cuMAC` scheduler lane specifically, contracts alone still do not prove
these future-expansion claims:

- the host boundary exists
- the placeholder adapter exists
- external scheduler worker proof does not yet exist
- runtime timing proof does not yet exist
- attach-validation proof does not yet exist

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
- `target-profile-family-bundle-v1.schema.json`
- `compare-report-v1.schema.json`
- `rollback-evidence-v1.schema.json`
- `open5gs-core-link-profile-v1.schema.json`

The immediate rule is simple:

- define contracts before runtime ownership expands
- keep the contracts additive to the existing `ranctl` model
- do not hide runtime-only assumptions in unversioned notes
- require a family bundle before any broader RU/core/profile claim leaves roadmap-only status

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
- [target-profile-family-bundle-v1.schema.json](target-profile-family-bundle-v1.schema.json)
- [examples/n79-single-ru-target-profile-v1.example.json](examples/n79-single-ru-target-profile-v1.example.json)
- [examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json](examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json)
- [examples/open5gs-core-link-profile-v1.example.json](examples/open5gs-core-link-profile-v1.example.json)
- [examples/n79-single-ru-single-ue-open5gs-family-bundle-v1.example.json](examples/n79-single-ru-single-ue-open5gs-family-bundle-v1.example.json)
- [compare-report-v1.schema.json](compare-report-v1.schema.json)
- [rollback-evidence-v1.schema.json](rollback-evidence-v1.schema.json)
- [open5gs-core-link-profile-v1.schema.json](open5gs-core-link-profile-v1.schema.json)
