defmodule AerialAdapter.ExecutionWorker do
  alias AerialAdapter.DeviceSession
  alias AerialAdapter.ExecutionProbe

  def initial_state do
    %{
      execution_status: "idle",
      device_surface: "clean_room://gpu-sim",
      policy_checkpoint: "bootstrap",
      lane_checkpoint: "idle",
      timing_budget_us: 400,
      deadline_state: "idle",
      last_batch_signature: [],
      last_execution_action: "boot"
    }
    |> Map.merge(DeviceSession.initial_state())
    |> Map.merge(ExecutionProbe.initial_state())
  end

  def open_session(state) do
    state
    |> Map.put(:execution_status, "session_open")
    |> Map.put(:device_surface, "#{state.vendor_surface}://execution")
    |> Map.put(:policy_checkpoint, "session_open")
    |> Map.put(:lane_checkpoint, state.execution_lane)
    |> Map.put(:timing_budget_us, state.batch_window_us)
    |> Map.put(:last_execution_action, "open_session")
    |> DeviceSession.open_session()
    |> ExecutionProbe.open_session()
  end

  def activate_cell(state) do
    next_state =
      state
      |> Map.put(:execution_status, "active")
      |> Map.put(:policy_checkpoint, "cell_active")
      |> Map.put(:lane_checkpoint, state.execution_lane)
      |> Map.put(:last_execution_action, "activate_cell")
      |> DeviceSession.activate_cell()

    case ExecutionProbe.activate_cell(next_state) do
      {:ok, active_state} -> {:ok, active_state}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit_slot(state, ir) do
    last_batch_signature =
      ir["messages"]
      |> List.wrap()
      |> Enum.map(& &1["kind"])

    deadline_state =
      if state.last_submit_cost_us > state.batch_window_us do
        "deadline_missed"
      else
        "within_budget"
      end

    state
    |> Map.put(:execution_status, "dispatching")
    |> Map.put(:policy_checkpoint, "slot_dispatched")
    |> Map.put(:lane_checkpoint, state.execution_lane)
    |> Map.put(:timing_budget_us, state.batch_window_us)
    |> Map.put(:deadline_state, deadline_state)
    |> Map.put(:last_batch_signature, last_batch_signature)
    |> Map.put(:last_execution_action, "submit_slot")
  end

  def uplink_indication(state) do
    state
    |> Map.put(:execution_status, "uplink_buffered")
    |> Map.put(:policy_checkpoint, "uplink_buffered")
    |> Map.put(:last_execution_action, "uplink_indication")
  end

  def quiesce(state, reason) do
    state
    |> Map.put(:execution_status, "quiesced")
    |> Map.put(:policy_checkpoint, "drain:#{reason}")
    |> Map.put(:last_execution_action, "quiesce")
    |> DeviceSession.quiesce()
    |> ExecutionProbe.quiesce()
  end

  def resume(state) do
    next_state =
      state
      |> Map.put(:execution_status, "active")
      |> Map.put(:policy_checkpoint, "resumed")
      |> Map.put(:lane_checkpoint, state.execution_lane)
      |> Map.put(:last_execution_action, "resume")
      |> DeviceSession.resume()

    case ExecutionProbe.resume(next_state) do
      {:ok, resumed_state} -> {:ok, resumed_state}
      {:error, reason} -> {:error, reason}
    end
  end

  def terminate(state) do
    state
    |> Map.put(:execution_status, "terminated")
    |> Map.put(:last_execution_action, "terminate")
    |> DeviceSession.terminate()
    |> ExecutionProbe.terminate()
  end

  def health_checks(state) do
    %{
      execution_status: state.execution_status,
      device_surface: state.device_surface,
      policy_checkpoint: state.policy_checkpoint,
      lane_checkpoint: state.lane_checkpoint,
      timing_budget_us: state.timing_budget_us,
      deadline_state: state.deadline_state,
      last_batch_signature: state.last_batch_signature,
      last_execution_action: state.last_execution_action
    }
    |> Map.merge(DeviceSession.health_checks(state))
    |> Map.merge(ExecutionProbe.health_checks(state))
  end
end
