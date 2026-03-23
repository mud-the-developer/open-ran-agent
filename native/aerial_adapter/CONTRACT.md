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
