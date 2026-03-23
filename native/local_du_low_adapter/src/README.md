# local_du_low Adapter Source

`bin/contract_gateway` is now only a wrapper.

`contract_gateway.exs` under this directory holds the adapter-local runtime entrypoint.
`handler.exs` holds the adapter-local Port contract bridge.
`transport_worker.exs` holds the fronthaul/session worker scaffold.
`device_session.exs` holds the device-session context scaffold behind that worker.
`transport_probe.exs` holds the handshake and host-probe scaffold behind that worker, including opt-in `strict_host_probe` gating for missing interface, device path, or PCI bindings.

This directory now carries the repository-owned transport/session worker scaffold, including queue and timing lifecycle state, while remaining the landing zone for future native runtime integration.
