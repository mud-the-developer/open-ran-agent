# aerial Adapter Contract Placeholder

## Role

`aerial_adapter` is the future native backend target for NVIDIA Aerial integration.

## Must Implement

- the same canonical backend behaviour as `local_du_low_adapter`
- capability advertisement through profile selection
- controlled failover and rollback hooks
- health reporting compatible with `ranctl` verification

## Guardrails

- do not encode vendor internals into BEAM-facing contracts
- do not assume cuBB or cuPHY implementation details in this repository

## Bootstrap Status

This adapter now includes an executable clean-room Port worker for contract validation.
Its adapter-local Port contract bridge lives under `src/handler.exs`.
Its clean-room execution/policy worker scaffold lives under `src/execution_worker.exs`.
Its device-session context scaffold lives under `src/device_session.exs`.
Real vendor integration remains deferred.

## Explicit Non-Claims

The current repo does **not** claim any of the following for `aerial_fapi_profile`:

- vendor device bring-up
- attach-plus-ping proof on a real Aerial-backed lane
- production timing, throughput, or latency guarantees

## Promotion Criteria

Before the repo can promote `aerial_fapi_profile` beyond roadmap-only status, it
must have reviewable evidence for all of the following:

- a declared target profile for the exact Aerial-backed lane
- host-probe evidence that the required device/runtime boundary is present
- a target-host deploy path that exercises the adapter beyond local scaffolding
- `verify` / `rollback` evidence tied to deterministic artifacts
- a stable runtime health model that operators can inspect without vendor archaeology
