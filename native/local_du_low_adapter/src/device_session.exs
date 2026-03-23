defmodule LocalDuLowAdapter.DeviceSession do
  def initial_state do
    %{
      device_session_ref: nil,
      device_session_state: "detached",
      device_generation: nil,
      device_profile: "loopback",
      device_owner: "repo.local_du_low",
      last_device_attach_at: nil,
      last_device_detach_at: nil
    }
  end

  def open_session(state) do
    now = now_iso8601()
    fronthaul_session = state.fronthaul_session || "local_du_low_port"

    state
    |> Map.put(:device_session_ref, "local_du_low://#{fronthaul_session}/device_session")
    |> Map.put(:device_session_state, "attached")
    |> Map.put(:device_generation, System.system_time(:microsecond))
    |> Map.put(:device_profile, "fronthaul_loopback")
    |> Map.put(:last_device_attach_at, now)
    |> Map.put(:last_device_detach_at, nil)
  end

  def activate_cell(state) do
    Map.put(state, :device_session_state, "active")
  end

  def quiesce(state) do
    Map.put(state, :device_session_state, "draining")
  end

  def resume(state) do
    Map.put(state, :device_session_state, "active")
  end

  def terminate(state) do
    state
    |> Map.put(:device_session_state, "terminated")
    |> Map.put(:last_device_detach_at, now_iso8601())
  end

  def health_checks(state) do
    %{
      device_session_ref: state.device_session_ref,
      device_session_state: state.device_session_state,
      device_generation: state.device_generation,
      device_profile: state.device_profile,
      device_owner: state.device_owner,
      last_device_attach_at: state.last_device_attach_at,
      last_device_detach_at: state.last_device_detach_at
    }
  end

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
