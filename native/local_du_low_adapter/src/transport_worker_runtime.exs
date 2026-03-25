Code.require_file("./device_session.exs", __DIR__)
Code.require_file("./transport_probe.exs", __DIR__)
Code.require_file("./transport_worker.exs", __DIR__)

defmodule LocalDuLowAdapter.TransportWorkerRuntime do
  alias LocalDuLowAdapter.TransportWorker

  def run do
    set_stdio_binary_mode()
    loop(TransportWorker.initial_state())
  end

  defp loop(state) do
    case IO.binread(:stdio, 4) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      <<length::unsigned-big-32>> ->
        payload = IO.binread(:stdio, length)
        request = :erlang.binary_to_term(payload, [:safe])
        {reply, next_state, halt?} = handle(request, state)
        encoded = :erlang.term_to_binary(reply)

        case safe_binwrite(<<byte_size(encoded)::unsigned-big-32, encoded::binary>>) do
          :ok ->
            unless halt? do
              loop(next_state)
            end

          :halt ->
            :ok
        end
    end
  end

  defp handle(%{command: :open_session, payload: payload}, state) do
    next_state =
      state
      |> Map.put(:fronthaul_session, Map.get(payload, :fronthaul_session, "local_du_low_port"))
      |> Map.put(:transport_worker, Map.get(payload, :transport_worker, "local_ring_v1"))
      |> Map.put(:slot_budget_us, Map.get(payload, :slot_budget_us, 200))
      |> Map.put(:session_payload, Map.get(payload, :session_payload, %{}))
      |> TransportWorker.open_session()

    payload = %{
      device_binding: next_state.device_binding,
      queue_target: next_state.queue_target,
      transport_status: next_state.transport_status
    }

    {ok_reply(payload, next_state), next_state, false}
  end

  defp handle(%{command: :activate_cell}, state) do
    case TransportWorker.activate_cell(state) do
      {:ok, next_state} ->
        payload = %{
          transport_status: next_state.transport_status,
          device_binding: next_state.device_binding
        }

        {ok_reply(payload, next_state), next_state, false}

      {:error, reason} ->
        {error_reply(reason, state), state, false}
    end
  end

  defp handle(%{command: :submit_slot, payload: payload}, state) do
    next_state =
      state
      |> Map.put(:last_submit_cost_us, Map.get(payload, :last_submit_cost_us, 0))
      |> Map.put(:slot_budget_us, Map.get(payload, :slot_budget_us, state.slot_budget_us))
      |> TransportWorker.submit_slot(Map.get(payload, :ir, %{}))

    reply_payload = %{
      submit_window_state: next_state.submit_window_state,
      last_slot_ref: next_state.last_slot_ref
    }

    {ok_reply(reply_payload, next_state), next_state, false}
  end

  defp handle(%{command: :uplink_indication}, state) do
    next_state = TransportWorker.uplink_indication(state)
    {ok_reply(%{transport_status: next_state.transport_status}, next_state), next_state, false}
  end

  defp handle(%{command: :quiesce}, state) do
    next_state = TransportWorker.quiesce(state)
    {ok_reply(%{transport_status: next_state.transport_status}, next_state), next_state, false}
  end

  defp handle(%{command: :resume}, state) do
    case TransportWorker.resume(state) do
      {:ok, next_state} ->
        {ok_reply(%{transport_status: next_state.transport_status}, next_state), next_state,
         false}

      {:error, reason} ->
        {error_reply(reason, state), state, false}
    end
  end

  defp handle(%{command: :health_check}, state) do
    {ok_reply(%{}, state), state, false}
  end

  defp handle(%{command: :terminate}, state) do
    next_state = TransportWorker.terminate(state)
    {ok_reply(%{transport_status: next_state.transport_status}, next_state), next_state, true}
  end

  defp handle(_request, state) do
    {error_reply(:unsupported_command, state), state, false}
  end

  defp ok_reply(payload, state) do
    %{
      status: :ok,
      payload: payload,
      checks: TransportWorker.health_checks(state)
    }
  end

  defp error_reply(reason, state) do
    %{
      status: :error,
      error: reason,
      checks: TransportWorker.health_checks(state)
    }
  end

  defp safe_binwrite(payload) do
    case IO.binwrite(:stdio, payload) do
      :ok -> :ok
      {:error, :terminated} -> :halt
      {:error, :epipe} -> :halt
      {:error, _reason} -> :halt
    end
  catch
    :error, :terminated -> :halt
    :error, :epipe -> :halt
    :exit, {:terminated, _reason} -> :halt
  end

  defp set_stdio_binary_mode do
    for device <- [:stdio, :standard_io] do
      try do
        _ = :io.setopts(device, encoding: :latin1)
      rescue
        _ -> :ok
      end
    end
  end
end
