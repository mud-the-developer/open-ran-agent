defmodule LocalDuLowAdapter.TransportWorker do
  alias LocalDuLowAdapter.DeviceSession
  alias LocalDuLowAdapter.TransportProbe

  def initial_state do
    %{
      transport_status: "idle",
      device_binding: "local_du_low://loopback",
      queue_target: "uplink_ring",
      queue_high_watermark: 8,
      last_slot_ref: nil,
      submit_window_state: "idle",
      last_transport_action: "boot"
    }
    |> Map.merge(DeviceSession.initial_state())
    |> Map.merge(TransportProbe.initial_state())
  end

  def open_session(state) do
    fronthaul_session = state.fronthaul_session || "local_du_low_port"

    state
    |> Map.put(:transport_status, "session_open")
    |> Map.put(:device_binding, "local_du_low://#{fronthaul_session}")
    |> Map.put(:queue_target, "#{fronthaul_session}:uplink_ring")
    |> Map.put(:last_transport_action, "open_session")
    |> DeviceSession.open_session()
    |> TransportProbe.open_session()
  end

  def activate_cell(state) do
    next_state =
      state
      |> Map.put(:transport_status, "active")
      |> Map.put(:last_transport_action, "activate_cell")
      |> DeviceSession.activate_cell()

    case TransportProbe.activate_cell(next_state) do
      {:ok, active_state} -> {:ok, active_state}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit_slot(state, ir) do
    submit_window_state =
      if state.last_submit_cost_us > state.slot_budget_us do
        "deadline_missed"
      else
        "within_budget"
      end

    state
    |> Map.put(:transport_status, "streaming")
    |> Map.put(:last_transport_action, "submit_slot")
    |> Map.put(:submit_window_state, submit_window_state)
    |> Map.put(:last_slot_ref, slot_ref(ir))
  end

  def uplink_indication(state) do
    state
    |> Map.put(:transport_status, "uplink_buffered")
    |> Map.put(:last_transport_action, "uplink_indication")
  end

  def quiesce(state) do
    state
    |> Map.put(:transport_status, "draining")
    |> Map.put(:last_transport_action, "quiesce")
    |> DeviceSession.quiesce()
    |> TransportProbe.quiesce()
  end

  def resume(state) do
    next_state =
      state
      |> Map.put(:transport_status, "active")
      |> Map.put(:last_transport_action, "resume")
      |> DeviceSession.resume()

    case TransportProbe.resume(next_state) do
      {:ok, resumed_state} -> {:ok, resumed_state}
      {:error, reason} -> {:error, reason}
    end
  end

  def terminate(state) do
    state
    |> Map.put(:transport_status, "terminated")
    |> Map.put(:last_transport_action, "terminate")
    |> DeviceSession.terminate()
    |> TransportProbe.terminate()
  end

  def health_checks(state) do
    %{
      transport_status: state.transport_status,
      device_binding: state.device_binding,
      queue_target: state.queue_target,
      queue_high_watermark: state.queue_high_watermark,
      last_slot_ref: state.last_slot_ref,
      submit_window_state: state.submit_window_state,
      last_transport_action: state.last_transport_action
    }
    |> Map.merge(DeviceSession.health_checks(state))
    |> Map.merge(TransportProbe.health_checks(state))
  end

  defp slot_ref(ir) do
    frame = ir["frame"]
    slot = ir["slot"]
    "#{frame}:#{slot}"
  end
end
