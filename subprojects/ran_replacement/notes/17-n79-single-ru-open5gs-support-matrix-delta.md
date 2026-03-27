# n79 Single-RU Open5GS Support-Matrix Delta

Status: draft

## Goal

Record the family-specific delta for the current `n79_single_ru_single_ue_lab_v1`
lane so broader profile expansion cannot silently reuse the baseline milestone-1
support matrices as a catch-all claim surface.

This note is intentionally narrow:

- one `n79` target-profile family
- one real single-RU family
- one real `Open5GS` core family
- one attach-plus-ping evidence bundle

## Family Identity

- target profile: `n79_single_ru_single_ue_lab_v1`
- profile family: `n79_single_ru_single_ue_open5gs_family_v1`
- RU family: `single_ru_ecpri_ptp_lab_v1`
- core family: `open5gs_nsa_lab_v1`

## Baseline Inputs

This family delta inherits the current milestone-1 baseline from:

- `09-ngap-procedure-support-matrix.md`
- `10-f1-c-and-e1ap-procedure-support-matrix.md`
- `11-f1-u-and-gtpu-procedure-support-matrix.md`

The delta below exists so those baseline notes stay reusable and do not become
implicit proof for unrelated RU/core/profile families.

## Declared Delta

### `NGAP`

- keep the baseline procedure set unchanged for this family
- keep the real-core endpoint fixed to `open5gs_nsa_lab_v1`
- do not imply registration proof for other core releases, AMF shapes, or UE classes

### `F1-C` And `E1AP`

- keep the control-plane evidence pinned to the single-RU, single-UE, single-host lane
- do not treat the baseline as proof for multi-cell, multi-DU, or scheduler-family expansion
- require an explicit sibling delta before claiming a different DU, scheduler, or control-plane family

### `F1-U` And `GTP-U`

- keep the user-plane evidence pinned to one declared UE session and one declared route
- do not stretch the current ping failure and rollback artifacts into proof for other forwarding or tunnel families
- require a new family bundle if the tunnel path, UE class, or core-session assumptions change materially

## Evidence Bundle

The current family-specific evidence bundle lives under:

- `subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/`

It currently includes:

- registration-rejected compare report
- ping-failed compare report
- failed-cutover rollback evidence

Those files prove only this family and must not be cited as evidence for a
different RU/core/profile family.

## Expansion Rule

Any new broader profile lane must add a sibling family delta note and sibling
family bundle before it is allowed to claim:

- broader RU vendor/class coverage
- broader core-profile coverage
- broader target-profile coverage
- multi-cell or multi-DU parity

If a future lane cannot name its own family bundle, it is still roadmap-only.
