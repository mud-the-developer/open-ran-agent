defmodule AerialAdapter.Handler do
  @behaviour NativeContractGateway.Handler
  alias NativeContractGateway.TransportLifecycle
  alias AerialAdapter.ExecutionWorker

  @impl true
  def initial_state do
    TransportLifecycle.new(%{
      execution_lane: "gpu_batch",
      batch_window_us: 400,
      timing_window_us: 400,
      policy_mode: "clean_room",
      vendor_surface: "opaque",
      last_message_kinds: [],
      last_batch_class: "idle",
      uplink_queue_depth: 0
    })
    |> Map.merge(ExecutionWorker.initial_state())
  end

  @impl true
  def on_open_session(message, state) do
    payload = message["payload"] || %{}
    session_payload = payload["session_payload"] || %{}

    next_state =
      state
      |> Map.put(
        :execution_lane,
        session_payload["execution_lane"] || payload["execution_lane"] || state.execution_lane
      )
      |> Map.put(
        :batch_window_us,
        session_payload["batch_window_us"] || payload["batch_window_us"] ||
          state.batch_window_us
      )
      |> Map.put(
        :vendor_surface,
        session_payload["vendor_surface"] || payload["vendor_surface"] || state.vendor_surface
      )
      |> TransportLifecycle.open_session(
        timing_window_us:
          session_payload["batch_window_us"] || payload["batch_window_us"] ||
            state.batch_window_us,
        transport_queue_depth: state.uplink_queue_depth
      )
      |> ExecutionWorker.open_session()

    {:ok,
     %{
       vendor_surface: next_state.vendor_surface,
       execution_lane: next_state.execution_lane,
       batch_window_us: next_state.batch_window_us,
       device_surface: next_state.device_surface
     }, next_state}
  end

  @impl true
  def on_activate_cell(_message, state) do
    case ExecutionWorker.activate_cell(state) do
      {:ok, next_state} ->
        {:ok,
         %{
           vendor_surface: state.vendor_surface,
           policy_mode: state.policy_mode
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

    reduced_depth = max(state.uplink_queue_depth - 1, 0)

    next_state =
      state
      |> Map.put(:last_message_kinds, last_message_kinds)
      |> Map.put(:last_batch_class, batch_class(last_message_kinds))
      |> Map.put(:uplink_queue_depth, reduced_depth)
      |> TransportLifecycle.submit(
        batch_size: length(last_message_kinds),
        timing_window_us: state.batch_window_us,
        transport_queue_depth: reduced_depth,
        unit_cost_us: 160
      )
      |> ExecutionWorker.submit_slot(ir)

    {:ok,
     %{
       batch_class: next_state.last_batch_class,
       execution_lane: state.execution_lane,
       deadline_state: next_state.deadline_state
     }, next_state}
  end

  @impl true
  def on_health_check(state) do
    %{
      vendor_surface: state.vendor_surface,
      policy_mode: state.policy_mode,
      execution_lane: state.execution_lane,
      batch_window_us: state.batch_window_us,
      last_message_kinds: state.last_message_kinds,
      last_batch_class: state.last_batch_class,
      uplink_queue_depth: state.uplink_queue_depth
    }
    |> Map.merge(TransportLifecycle.health_checks(state))
    |> Map.merge(ExecutionWorker.health_checks(state))
  end

  @impl true
  def on_uplink_indication(_message, state) do
    next_depth = state.uplink_queue_depth + 1

    next_state =
      state
      |> Map.put(:uplink_queue_depth, next_depth)
      |> TransportLifecycle.uplink(transport_queue_depth: next_depth)
      |> ExecutionWorker.uplink_indication()

    {:ok, %{uplink_queue_depth: next_state.uplink_queue_depth}, next_state}
  end

  @impl true
  def on_quiesce(message, state) do
    reason = get_in(message, ["payload", "reason"]) || "quiesce"

    next_state =
      state
      |> TransportLifecycle.quiesce(reason)
      |> ExecutionWorker.quiesce(reason)

    {:ok, %{policy_mode: state.policy_mode}, next_state}
  end

  @impl true
  def on_resume(_message, state) do
    next_state =
      state
      |> TransportLifecycle.resume(
        timing_window_us: state.batch_window_us,
        transport_queue_depth: state.uplink_queue_depth
      )

    case ExecutionWorker.resume(next_state) do
      {:ok, resumed_state} -> {:ok, %{execution_lane: state.execution_lane}, resumed_state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_terminate(_message, state) do
    next_state = ExecutionWorker.terminate(state)
    {:ok, %{vendor_surface: state.vendor_surface}, next_state}
  end

  defp batch_class(message_kinds) do
    cond do
      Enum.any?(message_kinds, &(&1 == "ul_tti_request")) -> "uplink"
      Enum.any?(message_kinds, &(&1 == "dl_tti_request")) -> "downlink"
      true -> "control"
    end
  end
end
