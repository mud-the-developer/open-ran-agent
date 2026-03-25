# Open5GS Core And S/M/C/U Plane Scope

Status: draft

## Goal

Freeze the replacement track around a real external core and an explicit plane model.

This note interprets the shorthand `S/M/C/U plane` as:

- `S-plane`: sync and timing
- `M-plane`: management and operations
- `C-plane`: control signaling
- `U-plane`: user-plane data path

If the team uses slightly different naming later, the labels can change, but the ownership split must stay explicit.

## Core Assumption

Milestone 1 uses a real `Open5GS`-based core.

This replacement track is not a core-replacement effort.
It is a `CU/DU replacement` effort that must interoperate with a real core.

That means:

- the core is not a stub
- registration must be real
- PDU session establishment must be real
- ping must traverse the declared user-plane path

## Plane Model

### S-plane

This includes:

- timing and sync assumptions
- PTP or GPS dependencies
- host timing readiness
- RU timing readiness

This is a hard gate. If `S-plane` readiness is not clean, the attach path is not trustworthy.

### M-plane

This includes:

- configuration
- inventory
- preflight
- deploy preview
- readiness scoring
- logs, captures, and evidence
- dashboard and debug surfaces

This is the operator control lane and should remain aligned with `ranctl`.

### C-plane

This includes:

- `NGAP`
- `F1-C`
- `E1AP`
- RRC-facing control progression
- session-control state required for registration

For milestone 1, `C-plane` health must be evidenced against a real `Open5GS` core.

### U-plane

This includes:

- `F1-U`
- `GTP-U`
- user-plane forwarding
- PDU session traffic path
- ping path

For milestone 1, `U-plane` cannot be treated as optional because `attach + ping` is the real success criterion.

## Ownership Questions To Resolve

Each plane must answer:

- what the replacement lane owns
- what native workers own
- what the real `Open5GS` core owns
- what the target host owns
- what evidence proves the plane is healthy
- what rollback target exists

## Acceptance Rule

No milestone 1 success claim is valid unless:

- `S-plane` is healthy enough for a trustworthy radio run
- `M-plane` can explain the run and collect evidence
- `C-plane` completes real registration against `Open5GS`
- `U-plane` completes real data flow for ping

