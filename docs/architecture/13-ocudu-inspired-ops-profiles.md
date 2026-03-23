# OCUDU-Inspired Ops Profiles

## Goal

Borrow the operational strengths of the OCUDU or srsRAN application model without copying runtime internals:

- layered config overlays
- validator plus autoderive before launch
- effective-config export for operators
- explicit debug or metrics surface
- remote control and evidence retrieval that remains outside hot paths

## What we imported

The OCUDU reference used during bootstrap was the archived `srsRAN Project`, which now points operators to OCUDU.

The most useful patterns for this repo were:

- split example configs such as `configs/du_rf_b200_tdd_n78_20mhz.yml`, `configs/cu_cp.yml`, and `configs/cu_up.yml`
- appconfig schema, validation, and YAML export such as `apps/du/du_appconfig_cli11_schema.cpp`, `apps/du/du_appconfig_validators.cpp`, and `apps/du/du_appconfig_yaml_writer.cpp`
- application unit boundaries such as `apps/units/application_unit.h`
- remote command, tracing, and metrics service patterns such as `apps/services/remote_control/remote_command.h`, `apps/services/application_tracer.h`, and `configs/debug.yml`

## What changed here

`bin/ran-deploy-wizard` and `Deploy Studio` now use a profile-driven target-host staging flow.

Profiles:

- `stable_ops`
- `troubleshoot`
- `lab_attach`

Each profile contributes:

- bounded config overrides such as dashboard bind host, image pull behavior, and strict host probing
- operator-facing overlays and preferences
- operator runbook steps, stability tier, exposure posture, and recommended use-cases
- an explicit `deploy.profile.json` artifact
- an explicit `deploy.effective.json` artifact that captures the merged topology, request, and env maps
- an explicit `deploy.readiness.json` artifact that scores rollout readiness and records blockers or warnings

## Why this matters

This gives operators the same high-value behavior OCUDU exposes through layered appconfig without forcing our repo to adopt its runtime architecture.

Benefits:

- safer target-host bring-up
- better UX in `Deploy Studio`
- easier remote handoff review
- deterministic postmortem state via fetched effective config, deploy profile, deploy readiness, and debug pack artifacts

## Current limits

- profiles influence staging, operator UX, and evidence only; they do not replace backend-specific runtime integration
- real `local_du_low` and `aerial` transport integration is still pending
- full UE attach and ping remains a target-host validation task

For the operator failure workflow that consumes these profile artifacts, see [14-debug-and-evidence-workflow.md](14-debug-and-evidence-workflow.md).
