# DU-High Southbound Contract

## Goal

Define a backend-agnostic contract between DU-high and the timing-sensitive southbound layer.

The current bootstrap repository includes a contract-only executable path for this boundary:

- `RanDuHigh.run_slot/3`
- `RanSchedulerHost.CpuScheduler`
- `RanSchedulerHost.CumacScheduler`
- `RanFapiCore.Dispatcher`
- `RanFapiCore.Backends.StubBackend`
- `RanFapiCore.Backends.LocalDuLowBackend`
- `RanFapiCore.Backends.AerialBackend`

This path is for contract validation and tests only. It is not a live RT gateway.

## Layering

```text
ran_du_high
   |
   v
ran_scheduler_host
   |
   v
ran_fapi_core  -> canonical IR and backend profile negotiation
   |
   v
fapi_rt_gateway (Port sidecar)
   |
   +-- local_fapi_profile
   +-- aerial_fapi_profile
   `-- stub_fapi_profile
```

## Canonical IR

The IR is a normalized `slot_batch` that groups one scheduling decision and its southbound messages for a single slot.

```elixir
%RanFapiCore.IR{
  ir_version: "0.1",
  cell_group_id: "cg-001",
  ue_ref: "ue-0001",
  frame: 128,
  slot: 9,
  profile: :local_fapi_profile,
  messages: [
    %{kind: :dl_tti_request, payload: %{...}},
    %{kind: :tx_data_request, payload: %{...}}
  ],
  metadata: %{
    scheduler: :cpu_scheduler,
    trace_id: "trace-123",
    deadline_us: 200
  }
}
```

## Backend Behaviour

Backends must implement the following minimum contract:

- `capabilities/0`
- `open_session/1`
- `activate_cell/2`
- `submit_slot/2`
- `handle_uplink_indication/2`
- `health/1`
- `quiesce/2`
- `resume/1`
- `terminate/1`

## Scheduler Contract

`ran_scheduler_host` must normalize all scheduler implementations into one host-facing contract so DU-high can remain scheduler-agnostic.

Required callbacks:

- `capabilities/0`
- `init_session/1`
- `plan_slot/2`
- `quiesce/2`
- `resume/1`
- `terminate/1`

Required output shape from `plan_slot/2`:

```elixir
%{
  scheduler: :cpu_scheduler,
  slot_ref: %{frame: 128, slot: 9},
  ue_allocations: [],
  fapi_messages: [],
  metadata: %{}
}
```

## Shared Capability Model

Each backend advertises:

- supported profiles
- supported message kinds
- max cell groups
- timing model
- drain support
- rollback support
- artifact capture support
- supported health states

Example normalized capability:

```elixir
%RanFapiCore.Capability{
  profile: :stub_fapi_profile,
  supported_profiles: [:stub_fapi_profile],
  supported_message_kinds: [:dl_tti_request, :tx_data_request, :ul_tti_request],
  max_cell_groups: 1,
  timing_model: :slot_batch,
  drain_support: true,
  rollback_support: true,
  artifact_capture_support: true,
  supported_health_states: [:healthy, :degraded, :draining, :failed],
  status: :bootstrap,
  metadata: %{}
}
```

`ran_fapi_core` must validate canonical IR against this capability contract before any slot is submitted.

## Health Model

Gateway health is explicit and versionable. Backends return a normalized `RanFapiCore.Health` structure instead of plain atoms.

```elixir
%RanFapiCore.Health{
  state: :healthy,
  reason: nil,
  session_status: :active,
  restart_count: 0,
  checks: %{},
  last_transition_at: "2026-03-21T00:00:00Z"
}
```

Allowed states for the bootstrap contract:

- `healthy`
- `degraded`
- `draining`
- `failed`

## Managed Session Workflow

`RanFapiCore.GatewaySession` is now the managed contract for a long-lived backend session.

- init: resolve backend module, normalize capability, open session, activate cell
- submit: validate IR, negotiate message compatibility, submit slot, refresh health
- uplink indication: accept runtime indications, refresh health checks, and keep the same session contract
- quiesce: move session into `draining`
- quiesced submit: reject new slot submissions without mutating the session into `failed`
- resume: move session back to `healthy`
- restart: terminate native session, reopen it, reactivate the cell, increment `restart_count`

The dispatcher still supports the original short-lived bootstrap path, but the session contract is now available for failure-domain and restart testing.

`local_fapi_profile` and `aerial_fapi_profile` now share the same Port-backed bootstrap contract path as `stub_fapi_profile`, implemented through a common native runtime plus adapter-local transport/session timing scaffolds. They remain non-RT adapters, but they are no longer empty placeholders.

The shared native runtime lives under [native/common/contract_gateway](../../native/common/contract_gateway/README.md). Adapter-local state machines live under:

- [native/local_du_low_adapter/src](../../native/local_du_low_adapter/src/README.md)
- [native/aerial_adapter/src](../../native/aerial_adapter/src/README.md)

For the bootstrap Port sidecar, the session status contract is now explicit and is driven by adapter-local transport/session timing signals across the Port boundary:

- `idle`: session opened, cell not yet activated
- `active`: slot submissions accepted
- `quiesced`: controlled drain in progress, submissions rejected with `session_quiesced`

The same scaffold also carries the lifecycle signals for open, activate, submit, uplink indication, quiesce, resume, and terminate. The shared runtime owns framing, JSON dispatch, and generic session bookkeeping; the adapter-local contract bridge delegates transport identity, session metadata, drain/resume policy, queue/timing worker state, and health checks back to BEAM.

Host and device probe state is now part of that contract surface. Both `local_fapi_profile` and `aerial_fapi_profile` can mark a session as `blocked` before activation when `strict_host_probe` is enabled and required host resources are missing. This keeps bootstrap workers non-RT while still giving target-host validation a hard activation gate instead of a soft warning-only surface.

The current bootstrap contract also exports lightweight host observations with that probe result:

- `handshake_target`: operator-facing summary of the expected host-to-device handshake path
- `probe_observations`: adapter-specific observations such as interface sysfs state, file kind and size, PCI sysfs metadata, or manifest/env summaries

Strict probe gating now uses those observations, not only raw existence checks. For example, interface presence is separated from interface readiness, and file-path presence is separated from bounded openability for bootstrap-safe resource checks.

## Port Choice

The first gateway implementation uses a Port sidecar instead of a NIF.

Reasons:

- scheduler isolation
- crash containment
- easier native toolchain independence
- lower risk than a long-lived NIF for early RT-adjacent integration

The current Port stack is split into:

- a shared runtime that owns framing, request dispatch, and generic session bookkeeping
- adapter-local contract bridges plus worker scaffolds that own profile-specific transport/session timing, drain/resume semantics, and health surface
- executable wrapper scripts that only select the adapter entrypoint

The shared runtime now forces `latin1` stdio mode before entering the Port loop so the 4-byte frame header remains binary-safe even when high-bit bytes appear in the payload length prefix.

## Deferred Decisions

- exact binary encoding over the Port boundary
- whether some gateway framing should use Erlang terms or a language-neutral binary envelope
- exact uplink indication batching rules
