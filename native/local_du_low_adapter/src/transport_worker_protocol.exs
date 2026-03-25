defmodule LocalDuLowAdapter.TransportWorkerProtocol do
  @worker_command Path.expand("../bin/transport_worker", __DIR__)
  @worker_command_ref "native/local_du_low_adapter/bin/transport_worker"
  @worker_boundary "adapter_local_native_worker"
  @worker_protocol "stdio_term_v1"
  @request_timeout 5_000

  def initial_state do
    %{
      worker_boundary: @worker_boundary,
      worker_protocol: @worker_protocol,
      worker_command: @worker_command_ref,
      worker_status: "stopped",
      worker_port: nil,
      worker_os_pid: nil,
      worker_restart_count: 0,
      worker_last_error: nil,
      worker_last_exit_status: nil,
      worker_last_started_at: nil,
      worker_last_reply_at: nil,
      worker_cached_checks: %{}
    }
  end

  def open_session(state) do
    with {:ok, state} <- ensure_worker(state),
         {:ok, next_state, payload} <- request(state, :open_session, worker_open_payload(state)) do
      {:ok, next_state, payload}
    end
  end

  def activate_cell(state), do: request(state, :activate_cell, %{})

  def submit_slot(state, ir) do
    request(state, :submit_slot, %{
      ir: ir,
      last_submit_cost_us: state.last_submit_cost_us,
      slot_budget_us: state.slot_budget_us
    })
  end

  def uplink_indication(state), do: request(state, :uplink_indication, %{})
  def quiesce(state, reason), do: request(state, :quiesce, %{reason: reason})

  def resume(state) do
    with {:ok, recovered_state} <- ensure_recovered_worker(state),
         {:ok, next_state, payload} <- request(recovered_state, :resume, %{}) do
      {:ok, next_state, payload}
    end
  end

  def terminate(state) do
    state = drain_worker_exit(state)

    case worker_alive?(state) do
      true ->
        case request(state, :terminate, %{}) do
          {:ok, next_state, payload} -> {:ok, stop_worker(next_state), payload}
          {:error, _reason, failed_state} -> {:ok, stop_worker(failed_state), %{}}
        end

      false ->
        {:ok, stop_worker(state), %{}}
    end
  end

  def health_checks(state) do
    state = drain_worker_exit(state)

    if worker_alive?(state) do
      case request(state, :health_check, %{}) do
        {:ok, next_state, _payload} ->
          {:ok, boundary_checks(next_state)}

        {:error, reason, failed_state} ->
          {:error, reason, boundary_checks(failed_state)}
      end
    else
      {:error, :transport_worker_down, boundary_checks(state)}
    end
  end

  defp ensure_recovered_worker(state) do
    state = drain_worker_exit(state)

    if worker_alive?(state) do
      {:ok, state}
    else
      with {:ok, started_state} <- ensure_worker(state),
           {:ok, reopened_state, _payload} <-
             request(started_state, :open_session, worker_open_payload(state)),
           {:ok, activated_state, _payload} <- request(reopened_state, :activate_cell, %{}) do
        {:ok, activated_state}
      end
    end
  end

  defp ensure_worker(state) do
    state = drain_worker_exit(state)

    if worker_alive?(state) do
      {:ok, refresh_worker_metadata(state)}
    else
      port =
        Port.open({:spawn_executable, @worker_command}, [
          :binary,
          :use_stdio,
          :exit_status,
          :stderr_to_stdout
        ])

      restart_count =
        if state.worker_last_started_at do
          state.worker_restart_count + 1
        else
          state.worker_restart_count
        end

      {:ok,
       state
       |> Map.put(:worker_port, port)
       |> Map.put(:worker_status, "running")
       |> Map.put(:worker_os_pid, port_os_pid(port))
       |> Map.put(:worker_restart_count, restart_count)
       |> Map.put(:worker_last_error, nil)
       |> Map.put(:worker_last_started_at, now_iso8601())}
    end
  end

  defp request(state, command, payload) do
    state = drain_worker_exit(state)

    if worker_alive?(state) do
      case Port.command(state.worker_port, encode_frame(%{command: command, payload: payload})) do
        true ->
          receive_reply(state)

        false ->
          failed_state = mark_worker_down(state, :transport_worker_down)
          {:error, :transport_worker_down, failed_state}
      end
    else
      failed_state = mark_worker_down(state, :transport_worker_down)
      {:error, :transport_worker_down, failed_state}
    end
  end

  defp receive_reply(state, buffer \\ "", timeout \\ @request_timeout) do
    receive do
      {port, {:data, chunk}} when port == state.worker_port ->
        case decode_frame(buffer <> chunk) do
          {:ok, reply, rest} ->
            next_state =
              state
              |> update_from_reply(reply)
              |> refresh_worker_metadata()

            if rest == "" do
              decode_reply(reply, next_state)
            else
              receive_reply(next_state, rest, timeout)
            end

          :more ->
            receive_reply(state, buffer <> chunk, timeout)

          {:error, reason} ->
            failed_state = mark_worker_down(state, reason)
            {:error, reason, failed_state}
        end

      {port, {:exit_status, status}} when port == state.worker_port ->
        failed_state =
          state
          |> Map.put(:worker_last_exit_status, status)
          |> mark_worker_down({:worker_exit, status})

        {:error, :transport_worker_down, failed_state}
    after
      timeout ->
        failed_state = mark_worker_down(state, :transport_worker_timeout)
        {:error, :transport_worker_timeout, failed_state}
    end
  end

  defp decode_reply(%{status: :ok, payload: payload}, state), do: {:ok, state, payload}

  defp decode_reply(%{status: :error, error: reason}, state), do: {:error, reason, state}

  defp update_from_reply(state, reply) do
    checks =
      reply
      |> Map.get(:checks, %{})
      |> stringify_keys()

    state
    |> Map.put(:worker_cached_checks, checks)
    |> Map.put(:worker_last_reply_at, now_iso8601())
    |> Map.put(:worker_last_error, nil)
    |> Map.put(:worker_status, "running")
  end

  defp drain_worker_exit(state) do
    case state.worker_port do
      port when is_port(port) ->
        receive do
          {^port, {:exit_status, status}} ->
            state
            |> Map.put(:worker_last_exit_status, status)
            |> mark_worker_down({:worker_exit, status})
            |> drain_worker_exit()
        after
          0 ->
            if Port.info(port) == nil do
              mark_worker_down(state, :transport_worker_down)
            else
              state
            end
        end

      _ ->
        state
    end
  end

  defp stop_worker(state) do
    case state.worker_port do
      port when is_port(port) ->
        if live_port?(port) do
          safe_port_close(port)
        end

      _ ->
        :ok
    end

    state
    |> Map.put(:worker_port, nil)
    |> Map.put(:worker_os_pid, nil)
    |> Map.put(:worker_status, "stopped")
  end

  defp refresh_worker_metadata(state) do
    Map.put(state, :worker_os_pid, port_os_pid(state.worker_port))
  end

  defp mark_worker_down(state, reason) do
    state
    |> Map.put(:worker_port, nil)
    |> Map.put(:worker_os_pid, nil)
    |> Map.put(:worker_status, "down")
    |> Map.put(:worker_last_error, normalize_reason(reason))
  end

  defp boundary_checks(state) do
    Map.merge(
      %{
        "worker_boundary" => state.worker_boundary,
        "worker_protocol" => state.worker_protocol,
        "worker_command" => state.worker_command,
        "worker_status" => state.worker_status,
        "worker_os_pid" => state.worker_os_pid,
        "worker_restart_count" => state.worker_restart_count,
        "worker_last_error" => state.worker_last_error,
        "worker_last_exit_status" => state.worker_last_exit_status,
        "worker_last_started_at" => state.worker_last_started_at,
        "worker_last_reply_at" => state.worker_last_reply_at
      },
      state.worker_cached_checks
    )
  end

  defp worker_open_payload(state) do
    %{
      fronthaul_session: state.fronthaul_session,
      transport_worker: state.transport_worker,
      slot_budget_us: state.slot_budget_us,
      session_payload: state.session_payload || %{}
    }
  end

  defp worker_alive?(state) do
    is_port(state.worker_port) and live_port?(state.worker_port)
  end

  defp port_os_pid(port) when is_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} when is_integer(os_pid) -> os_pid
      _ -> nil
    end
  end

  defp port_os_pid(_port), do: nil

  defp live_port?(port), do: Port.info(port) != nil

  defp encode_frame(term) do
    payload = :erlang.term_to_binary(term)
    <<byte_size(payload)::unsigned-big-32, payload::binary>>
  end

  defp decode_frame(<<length::unsigned-big-32, payload::binary-size(length), rest::binary>>) do
    {:ok, :erlang.binary_to_term(payload, [:safe]), rest}
  rescue
    ArgumentError -> {:error, :invalid_worker_reply}
  end

  defp decode_frame(_buffer), do: :more

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value

  defp normalize_reason({:worker_exit, status}), do: "worker_exit:#{status}"
  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason), do: inspect(reason)

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp safe_port_close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end
end
