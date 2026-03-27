# Target Profile: n79 Single-RU Single-UE Lab

Status: draft baseline for milestone 1

## Why This Profile Exists

The replacement track needs one sharply bounded proof target.

Without a fixed lab profile:

- parity claims become vague
- host assumptions drift
- RU timing issues get mixed with protocol issues
- "works on my lab" becomes unreviewable

This note defines the first acceptable proof target for the replacement program.

## Profile Name

`n79_single_ru_single_ue_lab_v1`

## Scope

- one gNB path
- one `CU-CP`
- one `CU-UP`
- one `DU`
- one real RU
- one real UE
- one real `Open5GS` core
- one target host
- one attach-plus-ping path

## RF And RAN Assumptions

These values must be pinned by the real lab owner before any parity claim is made:

- band: `n79`
- channel bandwidth
- numerology
- SCS
- TDD pattern
- PRB count
- antenna configuration
- PCI
- TAC
- PLMN

The replacement track is not allowed to claim success with "equivalent" settings on a different band or a different timing profile.

## RU Boundary Assumptions

The target profile must explicitly pin:

- RU vendor or class
- fronthaul mode
- sync source
- NIC or PCI ownership
- host-device mapping
- timing dependencies
- expected healthy indicators

At milestone 1, real RU ownership matters more than broad interoperability.

## UE Boundary Assumptions

The target profile must explicitly pin:

- UE device class
- band support
- SIM and subscriber assumptions
- logging path
- attach evidence path
- ping evidence path

## Core Boundary Assumptions

The target profile must explicitly pin:

- the `Open5GS` profile or release in use
- `N2` assumptions
- `N3` assumptions
- subscriber and DNN assumptions
- registration evidence path
- PDU session evidence path

## Host Boundary Assumptions

The target host must explicitly pin:

- OS and kernel baseline
- CPU isolation assumptions
- hugepages assumptions
- NIC ownership
- PTP or GPS assumptions
- timestamping assumptions
- deployment layout

## Acceptance Chain

Milestone 1 only counts as successful if this chain passes on the declared profile:

1. host preflight passes
2. RU readiness passes
3. gNB bring-up passes
4. control-plane health markers pass
5. attach passes
6. PDU session passes
7. ping passes

## Required Evidence

The profile is incomplete until it names the evidence path for:

- host preflight
- RU sync
- gNB runtime health
- attach logs
- ping result
- rollback target and rollback evidence

## What This Profile Does Not Mean

It does not mean:

- general `n79` support
- multi-RU support
- multi-cell support
- multi-DU support
- multi-UE support
- handover support
- mobility parity outside the declared attach-plus-ping lane
- production parity for all labs
