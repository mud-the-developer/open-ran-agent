# Port Protocol

## Purpose

This document records the bootstrap wire contract currently exercised by `RanFapiCore.PortProtocol`, `RanFapiCore.PortGatewayClient`, and the synthetic sidecar at [synthetic_gateway](bin/synthetic_gateway).

## Frame Model

Each message on the Port boundary carries:

- `message_type`
- `protocol_version`
- `cell_group_id`
- `session_ref`
- `trace_id`
- `payload`

## Envelope

Frames are length-prefixed and language-neutral:

```text
+----------------------+--------------------------------------+
| 4-byte length prefix | UTF-8 JSON payload bytes            |
+----------------------+--------------------------------------+
```

Current encoding:

- 4-byte unsigned big-endian payload length
- JSON object payload
- protocol version `0.1`

Example request:

```json
{
  "message_type": "submit_slot_batch",
  "protocol_version": "0.1",
  "cell_group_id": "cg-001",
  "session_ref": "sess-42",
  "trace_id": "trace-submit-sess-42",
  "payload": {
    "ir": {
      "ir_version": "0.1",
      "cell_group_id": "cg-001",
      "frame": 128,
      "slot": 9,
      "profile": "stub_fapi_profile",
      "messages": [
        { "kind": "tx_data_request", "payload": { "pdus": [] } }
      ],
      "metadata": {
        "scheduler": "cpu_scheduler",
        "status": "planned"
      }
    }
  }
}
```

## Required Message Classes

- `open_session`
- `activate_cell`
- `submit_slot_batch`
- `uplink_indication`
- `health_check`
- `quiesce`
- `resume`
- `terminate`

## Reply Shape

Replies are also length-prefixed JSON.

Successful replies:

```json
{
  "status": "ok",
  "message_type": "health_check",
  "protocol_version": "0.1",
  "session_ref": "sess-42",
  "trace_id": "trace-health-sess-42",
  "payload": {
    "health": {
      "state": "healthy",
      "reason": null,
      "session_status": "active",
      "restart_count": 0,
      "checks": {
        "submitted_slots": 1,
        "uplink_indications": 1,
        "last_uplink_kind": "rx_data_indication"
      }
    }
  }
}
```

`payload.health.session_status` currently uses:

- `idle`: session opened but not yet activated for a cell group
- `active`: slot submissions are accepted
- `quiesced`: drain is active and slot submissions must be rejected

Failure replies must carry:

- `status = "error"`
- `message_type`
- `session_ref`
- `trace_id`
- `error`

## Rules

- message ordering must be deterministic within one `cell_group`
- the gateway must never embed LLM or agent logic
- failure replies must be explicit and machine-readable
- health and drain hooks must remain available even when submit fails
- `activate_cell` transitions the session to `active`
- `uplink_indication` is accepted in `active` and `quiesced` states and updates health checks
- `quiesce` transitions health to `draining` and session status to `quiesced`
- `resume` transitions health back to `healthy` and session status to `active`
- `submit_slot_batch` must fail with `error = "session_quiesced"` when the session is drained

## Bootstrap Runtime

The repository now includes a synthetic Port sidecar to validate the protocol end-to-end.

- executable: [synthetic_gateway](bin/synthetic_gateway)
- client: [port_gateway_client.ex](../../apps/ran_fapi_core/lib/ran_fapi_core/port_gateway_client.ex)
- wire codec: [port_protocol.ex](../../apps/ran_fapi_core/lib/ran_fapi_core/port_protocol.ex)
- backend path: [stub_backend.ex](../../apps/ran_fapi_core/lib/ran_fapi_core/backends/stub_backend.ex) with `transport: :port`

## Deferred Decisions

- exact error code taxonomy
- batch sizing and uplink indication chunking
- whether JSON stays only for bootstrap or is replaced by a denser binary schema
