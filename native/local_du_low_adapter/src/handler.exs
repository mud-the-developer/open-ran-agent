defmodule LocalDuLowAdapter.Handler do
  @behaviour NativeContractGateway.Handler
  alias NativeContractGateway.TransportLifecycle
  alias LocalDuLowAdapter.TransportWorker

  @impl true
  def initial_state do
    TransportLifecycle.new(%{
      fronthaul_session: "local_du_low_port",
      transport_worker: "local_ring_v1",
      uplink_ring_depth: 0,
      slot_budget_us: 200,
      timing_window_us: 200,
      last_message_kinds: [],
      drain_target: "none"
    })
    |> Map.merge(TransportWorker.initial_state())
  end

  @impl true
  def on_open_session(message, state) do
    payload = message["payload"] || %{}
    session_payload = payload["session_payload"] || %{}

    next_state =
      state
      |> Map.put(
        :fronthaul_session,
        session_payload["fronthaul_session"] || payload["fronthaul_session"] ||
          state.fronthaul_session
      )
      |> Map.put(
        :transport_worker,
        session_payload["transport_worker"] || payload["transport_worker"] ||
          state.transport_worker
      )
      |> Map.put(
        :slot_budget_us,
        session_payload["slot_budget_us"] || payload["slot_budget_us"] || state.slot_budget_us
      )
      |> TransportLifecycle.open_session(
        timing_window_us:
          session_payload["slot_budget_us"] || payload["slot_budget_us"] || state.slot_budget_us,
        transport_queue_depth: state.uplink_ring_depth
      )
      |> TransportWorker.open_session()

    {:ok,
     %{
       fronthaul_session: next_state.fronthaul_session,
       transport_worker: next_state.transport_worker,
       slot_budget_us: next_state.slot_budget_us,
       device_binding: next_state.device_binding
     }, next_state}
  end

  @impl true
  def on_activate_cell(_message, state) do
    case TransportWorker.activate_cell(state) do
      {:ok, next_state} ->
        {:ok,
         %{
           activation_mode: "single_cell",
           fronthaul_session: state.fronthaul_session
         }, next_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def on_submit_slot(message, state) do
    ir = get_in(message, ["payload", "ir"]) || %{}

    last_message_kinds =
      ir["messages"]
      |> List.wrap()
      |> Enum.map(& &1["kind"])

    reduced_depth = max(state.uplink_ring_depth - 1, 0)

    next_state =
      state
      |> Map.put(:last_message_kinds, last_message_kinds)
      |> Map.put(:uplink_ring_depth, reduced_depth)
      |> TransportLifecycle.submit(
        batch_size: length(last_message_kinds),
        timing_window_us: state.slot_budget_us,
        transport_queue_depth: reduced_depth,
        unit_cost_us: 110
      )
      |> TransportWorker.submit_slot(ir)

    {:ok,
     %{
       fronthaul_session: state.fronthaul_session,
       transport_worker: state.transport_worker,
       submit_window_state: next_state.submit_window_state
     }, next_state}
  end

  @impl true
  def on_health_check(state) do
    %{
      adapter_owner: "repo",
      integration_boundary: "native_port_sidecar",
      fronthaul_session: state.fronthaul_session,
      transport_worker: state.transport_worker,
      uplink_ring_depth: state.uplink_ring_depth,
      slot_budget_us: state.slot_budget_us,
      last_message_kinds: state.last_message_kinds,
      drain_target: state.drain_target
    }
    |> Map.merge(TransportLifecycle.health_checks(state))
    |> Map.merge(TransportWorker.health_checks(state))
  end

  @impl true
  def on_uplink_indication(_message, state) do
    next_depth = state.uplink_ring_depth + 1

    next_state =
      state
      |> Map.put(:uplink_ring_depth, next_depth)
      |> TransportLifecycle.uplink(transport_queue_depth: next_depth)
      |> TransportWorker.uplink_indication()

    {:ok, %{uplink_ring_depth: next_state.uplink_ring_depth}, next_state}
  end

  @impl true
  def on_quiesce(message, state) do
    reason = get_in(message, ["payload", "reason"]) || "quiesce"

    next_state =
      state
      |> Map.put(:drain_target, reason)
      |> TransportLifecycle.quiesce(reason)
      |> TransportWorker.quiesce()

    {:ok, %{drain_target: "cell_group"}, next_state}
  end

  @impl true
  def on_resume(_message, state) do
    next_state =
      state
      |> Map.put(:drain_target, "none")
      |> TransportLifecycle.resume(
        timing_window_us: state.slot_budget_us,
        transport_queue_depth: state.uplink_ring_depth
      )

    case TransportWorker.resume(next_state) do
      {:ok, resumed_state} -> {:ok, %{drain_target: "none"}, resumed_state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_terminate(_message, state) do
    next_state = TransportWorker.terminate(state)
    {:ok, %{fronthaul_session: state.fronthaul_session}, next_state}
  end
end
