# Contributing

## Scope

This repository is design-first. Changes should preserve the existing architecture boundaries:

- keep BEAM orchestration separate from native timing-sensitive work
- route operational mutations through `bin/ranctl`
- prefer docs, ADRs, and contract changes before large runtime implementation

## Before opening a PR

1. Update architecture docs or ADRs when a boundary or contract changes.
2. Keep public examples sanitized. Do not commit private lab configs, generated artifacts, or operator-specific secrets.
3. Run:

```bash
mix ci
```

## Public repo rules

- Do not commit private OAI, srsRAN, OCUDU, or lab-specific config files.
- Do not commit generated `artifacts/*`, crash dumps, or local tool state.
- Use the sanitized templates under `config/**/*.example` and `examples/**` as the public reference shape.

## Pull request expectations

- explain the change at the architecture or contract level
- mention any new operational risks
- mention verification performed
