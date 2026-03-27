# aerial Adapter Contract

## Role

`aerial_adapter` is the current clean-room backend target for the bounded
`Aerial` runtime support lane.

## Must Implement

- the same canonical backend behaviour as `local_du_low_adapter`
- capability advertisement through profile selection
- controlled failover and rollback hooks
- health reporting compatible with `ranctl` verification

## Guardrails

- do not encode vendor internals into BEAM-facing contracts
- do not assume cuBB or cuPHY implementation details in this repository

## Bootstrap Status

This adapter now includes an executable clean-room Port worker for runtime
validation.
Its adapter-local Port contract bridge lives under `src/handler.exs`.
Its clean-room execution/policy worker scaffold lives under `src/execution_worker.exs`.
Its device-session context scaffold lives under `src/device_session.exs`.
Current support posture:

- declared target profile: `aerial_clean_room_runtime_v1`
- verify evidence: gateway lifecycle and transport-state tests under
  `apps/ran_fapi_core/test/ran_fapi_core/`
- rollback evidence: gateway-session drain, resume, and restart coverage in the
  same test suite
- health and failure-domain refs: `docs/architecture/03-failure-domains.md`
  and `docs/architecture/04-du-high-southbound-contract.md`

Real vendor integration remains deferred.

## Explicit Non-Claims

The current repo does **not** claim any of the following for `aerial_fapi_profile`:

- vendor device bring-up
- attach-plus-ping proof on a real Aerial-backed lane
- production timing, throughput, or latency guarantees

## Further Expansion Criteria

Before the repo can promote `aerial_fapi_profile` beyond the current bounded
clean-room support lane, it must have reviewable evidence for all of the
following:

- vendor-backed device bring-up for the exact Aerial-backed lane
- a target-host deploy path that exercises the vendor runtime beyond
  clean-room scaffolding
- attach-plus-ping proof on that Aerial-backed lane
- production timing and throughput evidence tied to deterministic artifacts
