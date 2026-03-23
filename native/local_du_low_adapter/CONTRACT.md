# local_du_low Adapter Contract Placeholder

## Role

`local_du_low_adapter` is the repository-owned native backend target for a future DU-low / low-PHY integration path.

## Must Implement

- the canonical backend behaviour exposed by `ran_fapi_core`
- controlled drain and resume
- health reporting
- rollback-safe session termination

## Must Not Assume Yet

- concrete RU vendor specifics
- live fronthaul runtime details
- final binary framing choice

## Bootstrap Status

The adapter now includes an executable Port worker for contract validation.
Its adapter-local Port contract bridge lives under `src/handler.exs`.
Its repository-owned fronthaul/session worker scaffold lives under `src/transport_worker.exs`.
Its device-session context scaffold lives under `src/device_session.exs`.
Real device and fronthaul integration are still deferred.
