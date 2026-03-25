# RAN Replacement Workspace Rules

## Purpose

This workspace is for a clean-room `CU/DU replacement` track that targets a real `n79` lab with:

- one gNB path
- one RU path
- one UE attach-plus-ping path
- one real `Open5GS` core interop path
- explicit operator control through `../../bin/ranctl`
- explicit rollback, precheck, verify, and evidence

Treat this directory as a design-first workbench for:

- architecture notes
- protocol and lifecycle contracts
- target-host readiness definitions
- agent-friendly CLI surface definitions
- future replacement-track scaffolding

It is not permission to bypass the main repo rules or to put agent logic inside RT-sensitive runtime loops.

## Read First

- `../../README.md`
- `../../AGENTS.md`
- `../../docs/architecture/00-system-overview.md`
- `../../docs/architecture/04-du-high-southbound-contract.md`
- `../../docs/architecture/05-ranctl-action-model.md`
- `../../docs/architecture/07-mvp-scope-and-roadmap.md`
- `../../docs/architecture/08-open-questions-and-risks.md`
- `../../docs/adr/0002-beam-vs-native-boundary.md`
- `../../docs/adr/0004-ranctl-as-single-action-entrypoint.md`
- `../../docs/adr/0007-ran-functions-as-agent-friendly-cli-surface.md`

## Guardrails

- Do not put agent logic or LLM logic into slot-paced, scheduler-paced, or RT-sensitive datapaths.
- Do not bypass `../../bin/ranctl` for mutable actions.
- Do not copy OpenAirInterface implementation code into committed files.
- If upstream OAI or vendor references are cloned later, keep them under `upstream/` and keep them ignored.
- Do not commit private RU configs, UE configs, SIM data, IP plans, captures, secrets, tokens, or `.env` files.
- Keep BEAM control logic, native RT workers, and operator workflows as separate concerns.
- Prefer contracts, ADRs, and task plans before runtime implementation.

## Working Goal

The near-term goal is to define a replacement track that can eventually take over the visible `OAI CU/DU` role for a narrow real-lab target:

- `n79`
- one real RU
- one real UE
- one real `Open5GS` core
- one attach-plus-ping success path
- deterministic operator control through `ranctl`
- explicit rollback targets and evidence
- standards-correct external behavior for the declared supported interfaces

## First Deliverables

1. A detailed replacement task plan.
2. A resource and action taxonomy for agent-friendly CLI control.
3. A target lab profile note for `n79` RU, UE, timing, and transport assumptions.
4. A clean-room boundary note for what stays native or external.
