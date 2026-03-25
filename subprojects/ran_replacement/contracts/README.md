# RAN Replacement Contracts

This directory will hold draft contracts for the replacement track.

Planned first contracts:

- `ranctl-ran-replacement-request-v1.schema.json`
- `ranctl-ran-replacement-status-v1.schema.json`
- `n79-single-ru-target-profile-v1.schema.json`
- `open5gs-core-link-profile-v1.schema.json`

The immediate rule is simple:

- define contracts before runtime ownership expands
- keep the contracts additive to the existing `ranctl` model
- do not hide runtime-only assumptions in unversioned notes

Current draft files:

- [ranctl-ran-replacement-request-v1.schema.json](ranctl-ran-replacement-request-v1.schema.json)
- [ranctl-ran-replacement-status-v1.schema.json](ranctl-ran-replacement-status-v1.schema.json)
- [n79-single-ru-target-profile-v1.schema.json](n79-single-ru-target-profile-v1.schema.json)
- [examples/n79-single-ru-target-profile-v1.example.json](examples/n79-single-ru-target-profile-v1.example.json)
- [examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json](examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json)
- [open5gs-core-link-profile-v1.schema.json](open5gs-core-link-profile-v1.schema.json)
