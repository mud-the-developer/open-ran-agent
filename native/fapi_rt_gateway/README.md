# fapi_rt_gateway

This directory is the planned native gateway between BEAM-managed DU-high orchestration and RT-adjacent backend transport.

Current scope:

- define the gateway boundary
- keep backend-specific transport out of BEAM hot paths
- start with a Port-based sidecar model
- exercise a synthetic sidecar through the real framing contract

Deferred:

- real transport runtime
- benchmarking and latency tuning
