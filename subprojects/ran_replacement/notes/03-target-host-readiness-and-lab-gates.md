# Target-Host Readiness And Lab Gates

Status: draft

## Goal

Fail early and honestly before a risky live run begins.

## Readiness Layers

The replacement lane needs four readiness layers:

1. target-host readiness
2. RU readiness
3. runtime readiness
4. UE and attach readiness

## Target-Host Readiness

The target host should be blocked if any required dependency is missing:

- expected NIC or PCI inventory
- hugepages
- PTP or sync dependency
- required kernel features
- required install layout
- required topology and request files

## RU Readiness

The RU lane should be blocked if any required dependency is missing:

- expected sync
- expected reachable control link
- expected timing indicators
- expected host-to-device mapping

## Runtime Readiness

The runtime lane should be blocked if any required dependency is missing:

- config validation
- fallback runtime target
- approval evidence for destructive path
- expected precheck gates

## UE And Attach Readiness

The attach lane should be blocked if any required dependency is missing:

- subscriber assumptions
- UE band support
- registration path visibility
- ping target visibility

## Status Vocabulary

The readiness model should use stable terms:

- `blocked`
- `degraded`
- `ready_for_preflight`
- `ready_for_apply`

## Evidence Requirements

Every blocked or degraded state should point to:

- reason
- failed check
- required next action
- artifact or observation path

## Rule

The operator must be able to see why a run is blocked before touching live runtime.

