# Gateway Source Placeholder

Expected future contents:

- Port framing and decode logic
- backend session runtime
- health and drain hooks
- artifact capture hooks

Bootstrap note:

- the repository-level synthetic sidecar currently lives at [synthetic_gateway](../bin/synthetic_gateway)
- BEAM-side framing and client code live in [port_protocol.ex](../../../apps/ran_fapi_core/lib/ran_fapi_core/port_protocol.ex) and [port_gateway_client.ex](../../../apps/ran_fapi_core/lib/ran_fapi_core/port_gateway_client.ex)
