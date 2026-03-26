# Aerial Adapter Source

`bin/contract_gateway` is now only a wrapper.

`contract_gateway.exs` under this directory holds the adapter-local runtime entrypoint.
`handler.exs` holds the clean-room Port contract bridge.
`execution_worker.exs` holds the clean-room execution/policy worker scaffold.
`device_session.exs` holds the device-session context scaffold behind that worker.
`execution_probe.exs` holds the handshake and host-probe scaffold behind that worker, including opt-in `strict_host_probe` gating for missing vendor socket, manifest, or CUDA visibility markers.

This directory now holds the adapter-local contract entrypoint plus execution/timing worker scaffold, and remains the landing zone for future Aerial runtime code.

Until promotion criteria are met, this scaffold is only evidence for:

- clean-room contract ownership
- host-probe gating shape
- non-RT session/bootstrap behavior

It is not evidence for:

- vendor runtime bring-up
- real attach-plus-ping success on Aerial
- production timing guarantees
