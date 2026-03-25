# Boundaries And Protocol Ownership

Status: draft

## Goal

Make ownership explicit before runtime work starts.

The replacement track cannot succeed if "CU/DU replacement" means different things in different layers.
This is especially true now that milestone 1 assumes a real external `Open5GS` core and explicit `S/M/C/U` plane ownership.

## Ownership Categories

There are only three allowed ownership categories in this track:

- BEAM control ownership
- native RT ownership
- external infrastructure ownership

## Expected BEAM Ownership

The BEAM side is the likely owner for:

- lifecycle planning
- approval gating
- config validation
- topology modeling
- evidence writing
- dashboard state
- non-RT protocol orchestration and session control

## Expected Native Ownership

The native side is the likely owner for:

- RT-sensitive southbound transport
- queueing close to timing deadlines
- tight timing probes and handshake state
- RU-facing worker behavior

## Expected External Ownership

Some boundaries may remain external at milestone 1:

- PTP or GPS distribution
- host NIC and kernel tuning
- some fronthaul plumbing
- external core dependencies when replacement scope does not yet cover them

## Protocol Questions To Freeze

The track needs explicit notes for:

- `F1-C`
- `F1-U`
- `E1AP`
- `NGAP`
- `GTP-U`
- RU/fronthaul ownership
- timing and sync ownership
- ownership split against the real `Open5GS` core

Each protocol note should answer:

- who owns lifecycle
- who owns live runtime
- what verify evidence proves health
- what rollback target exists

## Boundary Smells

The design is drifting in the wrong direction if:

- a hot-path behavior depends on agent reasoning
- a cutover path bypasses `ranctl`
- runtime ownership is split without explicit evidence
- a native worker becomes a hidden shell script bag
- public claims exceed the declared target profile
