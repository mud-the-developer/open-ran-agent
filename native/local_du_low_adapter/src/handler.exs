defmodule LocalDuLowAdapter.Handler do
  @behaviour NativeContractGateway.Handler
  alias NativeContractGateway.TransportLifecycle
  alias LocalDuLowAdapter.TransportWorkerProtocol

  @integration_boundary "native_port_worker_boundary"

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
    |> Map.merge(TransportWorkerProtocol.initial_state())
  end

  @impl true
  def on_open_session(message, state) do
    payload = message["payload"] || %{}
    session_payload = payload["session_payload"] || %{}

    fronthaul_session =
      session_payload["fronthaul_session"] || payload["fronthaul_session"] ||
        state.fronthaul_session

    transport_worker =
      session_payload["transport_worker"] || payload["transport_worker"] || state.transport_worker

    slot_budget_us =
      session_payload["slot_budget_us"] || payload["slot_budget_us"] || state.slot_budget_us

    next_state =
      state
      |> Map.put(:fronthaul_session, fronthaul_session)
      |> Map.put(:transport_worker, transport_worker)
      |> Map.put(:slot_budget_us, slot_budget_us)
      |> Map.put(:session_payload, session_payload)
      |> TransportLifecycle.open_session(
        timing_window_us: slot_budget_us,
        transport_queue_depth: state.uplink_ring_depth
      )

    case TransportWorkerProtocol.open_session(next_state) do
      {:ok, opened_state, worker_payload} ->
        {:ok,
         %{
           fronthaul_session: fronthaul_session,
           transport_worker: transport_worker,
           slot_budget_us: slot_budget_us,
           device_binding: Map.get(worker_payload, :device_binding)
         }, opened_state}

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
    end
  end

  @impl true
  def on_activate_cell(_message, state) do
    case TransportWorkerProtocol.activate_cell(state) do
      {:ok, next_state, _worker_payload} ->
        {:ok,
         %{
           activation_mode: "single_cell",
           fronthaul_session: state.fronthaul_session
         }, next_state}

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
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

    case TransportWorkerProtocol.submit_slot(next_state, ir) do
      {:ok, submitted_state, worker_payload} ->
        {:ok,
         %{
           fronthaul_session: state.fronthaul_session,
           transport_worker: state.transport_worker,
           submit_window_state: Map.get(worker_payload, :submit_window_state)
         }, submitted_state}

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
    end
  end

  @impl true
  def on_health_check(state) do
    worker_checks =
      case TransportWorkerProtocol.health_checks(state) do
        {:ok, checks} -> checks
        {:error, _reason, checks} -> checks
      end

    base_checks(state)
    |> Map.merge(TransportLifecycle.health_checks(state))
    |> Map.merge(worker_checks)
  end

  @impl true
  def on_uplink_indication(_message, state) do
    next_depth = state.uplink_ring_depth + 1

    next_state =
      state
      |> Map.put(:uplink_ring_depth, next_depth)
      |> TransportLifecycle.uplink(transport_queue_depth: next_depth)

    case TransportWorkerProtocol.uplink_indication(next_state) do
      {:ok, updated_state, _worker_payload} ->
        {:ok, %{uplink_ring_depth: updated_state.uplink_ring_depth}, updated_state}

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
    end
  end

  @impl true
  def on_quiesce(message, state) do
    reason = get_in(message, ["payload", "reason"]) || "quiesce"

    next_state =
      state
      |> Map.put(:drain_target, reason)
      |> TransportLifecycle.quiesce(reason)

    case TransportWorkerProtocol.quiesce(next_state, reason) do
      {:ok, quiesced_state, _worker_payload} ->
        {:ok, %{drain_target: "cell_group"}, quiesced_state}

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
    end
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

    case TransportWorkerProtocol.resume(next_state) do
      {:ok, resumed_state, _worker_payload} -> {:ok, %{drain_target: "none"}, resumed_state}
      {:error, reason, failed_state} -> {:error, reason, failed_state}
    end
  end

  @impl true
  def on_terminate(_message, state) do
    case TransportWorkerProtocol.terminate(state) do
      {:ok, next_state, _worker_payload} ->
        {:ok, %{fronthaul_session: state.fronthaul_session}, next_state}

      {:error, reason, failed_state} ->
        {:error, reason, failed_state}
    end
  end

  defp base_checks(state) do
    %{
      adapter_owner: "repo",
      integration_boundary: @integration_boundary,
      fronthaul_session: state.fronthaul_session,
      transport_worker: state.transport_worker,
      uplink_ring_depth: state.uplink_ring_depth,
      slot_budget_us: state.slot_budget_us,
      last_message_kinds: state.last_message_kinds,
      drain_target: state.drain_target
    }
  end
end
