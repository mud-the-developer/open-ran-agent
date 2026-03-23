# ADR 0005: Ops Automation With Skills, Not MCP

## Status

Accepted

## Context

The repository brief explicitly excludes MCP and instead requires repo-local skill workflows paired with a deterministic executor.

## Decision

Use repo-local skill directories plus Symphony/Codex orchestration, with `ranctl` as the execution boundary.

The skill directories hold:

- procedural guidance
- prompt and workflow context
- optional thin wrapper scripts
- references to docs and examples

## Consequences

Positive:

- versioned operational procedures live in the repo
- no hidden external procedure layer
- easier review and change tracking

Negative:

- skill quality depends on disciplined maintenance
- approval and context handoff formats still need standardization

## Alternatives Considered

- MCP-based procedure integration: rejected by brief.
- Unstructured wiki and scripts: too hard to keep deterministic and reviewable.
