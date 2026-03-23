# Native Contract Gateway Shared Runtime

This directory holds the shared executable contract gateway runtime used by the repository-owned native adapter workers.

## Shared Responsibilities

- binary framing over the Port boundary
- JSON request and response decoding
- generic session lifecycle routing
- common health envelope assembly
- shared state transitions for open, activate, submit, quiesce, resume, and terminate
- deterministic forwarding of transport/session lifecycle signals to the adapter-local handler
- binary-safe stdio setup so Port frame headers are not re-encoded by the VM IO layer

## Adapter-Local Responsibilities

- initial adapter state
- adapter-specific open/session metadata
- transport/session timing scaffold and drain/resume policy
- adapter-local device-session context and worker state
- adapter-local handshake and host-probe scaffolds
- adapter-local strict host-probe gating before activation or resume
- adapter-local health checks
- adapter-local runtime state machines
- adapter-specific policy or transport identity fields

## Current Adapters

- `native/local_du_low_adapter/src/contract_gateway.exs`
- `native/local_du_low_adapter/src/handler.exs`
- `native/aerial_adapter/src/contract_gateway.exs`
- `native/aerial_adapter/src/handler.exs`

## Next Step

The next step is to replace the adapter-local bootstrap handlers with real transport workers:

- `local_du_low_adapter` should grow fronthaul/session transport and timing integration
- `aerial_adapter` should stay clean-room while wiring to the eventual vendor-native integration path

The shared runtime should remain stable while the adapter-local workers evolve from scaffold-only lifecycle handling into transport-aware workers with real timing, queueing, and device/session integration.
