defmodule NativeContractGateway.Runtime do
  def run(config) when is_map(config) do
    set_stdio_binary_mode()
    loop(initial_state(config), config)
  end

  defp initial_state(config) do
    base_state = %{
      session_ref: nil,
      cell_group_id: nil,
      submitted_slots: 0,
      uplink_indications: 0,
      last_uplink_kind: nil,
      last_batch_size: 0,
      activated_cells: 0,
      state: "healthy",
      restart_count: 0,
      session_status: "idle",
      accepted_profile: nil,
      dispatch_mode: Map.get(config, :default_dispatch_mode, "bootstrap"),
      session_payload: %{}
    }

    Map.merge(base_state, handler(config).initial_state())
  end

  defp loop(state, config) do
    case IO.binread(:stdio, 4) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      <<length::unsigned-big-32>> ->
        payload = IO.binread(:stdio, length)
        {:ok, message} = JSON.decode(payload)
        {reply, next_state, halt?} = handle(message, state, config)
        encoded = JSON.encode!(reply)

        case safe_binwrite(<<byte_size(encoded)::unsigned-big-32, encoded::binary>>) do
          :ok ->
            unless halt? do
              loop(next_state, config)
            end

          :halt ->
            :ok
        end
    end
  end

  defp handle(%{"message_type" => "open_session"} = message, state, config) do
    requested_profile = get_in(message, ["payload", "profile"])

    if requested_profile == config.supported_profile do
      dispatch_mode = get_in(message, ["payload", "dispatch_mode"]) || state.dispatch_mode
      session_payload = get_in(message, ["payload", "session_payload"]) || %{}

      case handler(config).on_open_session(message, %{state | session_payload: session_payload}) do
        {:ok, open_payload, next_state} ->
          payload =
            Map.merge(
              %{
                "session_ref" => message["session_ref"],
                "accepted_profile" => requested_profile,
                "dispatch_mode" => dispatch_mode,
                "worker_kind" => config.worker_kind
              },
              stringify_keys(open_payload)
            )

          {ok_reply(message, payload),
           state
           |> Map.merge(next_state)
           |> Map.merge(%{
             session_ref: message["session_ref"],
             cell_group_id: message["cell_group_id"],
             accepted_profile: requested_profile,
             dispatch_mode: dispatch_mode,
             session_payload: session_payload,
             session_status: "idle"
           }), false}

        {:error, reason, handler_state} ->
          {error_reply(message, error_reason(reason)),
           state
           |> Map.merge(handler_state)
           |> Map.put(:session_payload, session_payload), false}

        {:error, reason} ->
          {error_reply(message, error_reason(reason)), state, false}
      end
    else
      {error_reply(message, "unsupported_profile"), state, false}
    end
  end

  defp handle(%{"message_type" => "activate_cell"} = message, state, config) do
    next_state = %{
      state
      | cell_group_id: message["cell_group_id"],
        activated_cells: state.activated_cells + 1,
        session_status: "active"
    }

    case handler(config).on_activate_cell(message, next_state) do
      {:ok, activate_payload, handler_state} ->
        payload =
          Map.merge(
            %{
              "cell_group_id" => message["cell_group_id"],
              "activated_cells" => next_state.activated_cells
            },
            stringify_keys(activate_payload)
          )

        {ok_reply(message, payload), Map.merge(next_state, handler_state), false}

      {:error, reason, handler_state} ->
        {error_reply(message, error_reason(reason)), Map.merge(state, handler_state), false}

      {:error, reason} ->
        {error_reply(message, error_reason(reason)), state, false}
    end
  end

  defp handle(%{"message_type" => "submit_slot_batch"} = message, state, config) do
    cond do
      state.session_status == "quiesced" ->
        {error_reply(message, "session_quiesced"), state, false}

      state.session_status != "active" ->
        {error_reply(message, "session_not_active"), state, false}

      true ->
        ir = get_in(message, ["payload", "ir"]) || %{}
        message_count = ir["messages"] |> List.wrap() |> length()

        next_state = %{
          state
          | submitted_slots: state.submitted_slots + 1,
            last_batch_size: message_count
        }

        case handler(config).on_submit_slot(message, next_state) do
          {:ok, submit_payload, handler_state} ->
            payload =
              Map.merge(
                %{
                  "submitted_slots" => next_state.submitted_slots,
                  "last_slot_ref" => %{"frame" => ir["frame"], "slot" => ir["slot"]},
                  "last_batch_size" => message_count
                },
                stringify_keys(submit_payload)
              )

            {ok_reply(message, payload), Map.merge(next_state, handler_state), false}

          {:error, reason, handler_state} ->
            {error_reply(message, error_reason(reason)), Map.merge(state, handler_state), false}

          {:error, reason} ->
            {error_reply(message, error_reason(reason)), state, false}
        end
    end
  end

  defp handle(%{"message_type" => "health_check"} = message, state, config) do
    payload = %{
      "health" => %{
        "state" => state.state,
        "reason" => nil,
        "session_status" => state.session_status,
        "restart_count" => state.restart_count,
        "checks" =>
          Map.merge(
            %{
              "submitted_slots" => state.submitted_slots,
              "uplink_indications" => state.uplink_indications,
              "last_uplink_kind" => state.last_uplink_kind,
              "last_batch_size" => state.last_batch_size,
              "activated_cells" => state.activated_cells,
              "worker_kind" => config.worker_kind,
              "accepted_profile" => state.accepted_profile,
              "dispatch_mode" => state.dispatch_mode
            },
            stringify_keys(handler(config).on_health_check(state))
          )
      }
    }

    {ok_reply(message, payload), state, false}
  end

  defp handle(%{"message_type" => "uplink_indication"} = message, state, config) do
    if state.session_status in ["active", "quiesced"] do
      uplink = get_in(message, ["payload", "indication"]) || %{}
      kind = uplink["kind"]

      next_state = %{
        state
        | uplink_indications: state.uplink_indications + 1,
          last_uplink_kind: kind
      }

      case handler(config).on_uplink_indication(message, next_state) do
        {:ok, uplink_payload, handler_state} ->
          payload =
            Map.merge(
              %{
                "uplink_indications" => next_state.uplink_indications,
                "last_uplink_kind" => kind
              },
              stringify_keys(uplink_payload)
            )

          {ok_reply(message, payload), Map.merge(next_state, handler_state), false}

        {:error, reason, handler_state} ->
          {error_reply(message, error_reason(reason)), Map.merge(state, handler_state), false}

        {:error, reason} ->
          {error_reply(message, error_reason(reason)), state, false}
      end
    else
      {error_reply(message, "session_not_active"), state, false}
    end
  end

  defp handle(%{"message_type" => "quiesce"} = message, state, config) do
    next_state = %{state | state: "draining", session_status: "quiesced"}

    case handler(config).on_quiesce(message, next_state) do
      {:ok, quiesce_payload, handler_state} ->
        payload =
          Map.merge(
            %{"state" => "draining", "reason" => get_in(message, ["payload", "reason"])},
            stringify_keys(quiesce_payload)
          )

        {ok_reply(message, payload), Map.merge(next_state, handler_state), false}

      {:error, reason, handler_state} ->
        {error_reply(message, error_reason(reason)), Map.merge(state, handler_state), false}

      {:error, reason} ->
        {error_reply(message, error_reason(reason)), state, false}
    end
  end

  defp handle(%{"message_type" => "resume"} = message, state, config) do
    next_state = %{state | state: "healthy", session_status: "active"}

    case handler(config).on_resume(message, next_state) do
      {:ok, resume_payload, handler_state} ->
        payload = Map.merge(%{"state" => "healthy"}, stringify_keys(resume_payload))
        {ok_reply(message, payload), Map.merge(next_state, handler_state), false}

      {:error, reason, handler_state} ->
        {error_reply(message, error_reason(reason)), Map.merge(state, handler_state), false}

      {:error, reason} ->
        {error_reply(message, error_reason(reason)), state, false}
    end
  end

  defp handle(%{"message_type" => "terminate"} = message, state, config) do
    case handler(config).on_terminate(message, state) do
      {:ok, terminate_payload, handler_state} ->
        payload = Map.merge(%{"terminated" => true}, stringify_keys(terminate_payload))
        {ok_reply(message, payload), Map.merge(state, handler_state), true}

      {:error, reason, handler_state} ->
        {error_reply(message, error_reason(reason)), Map.merge(state, handler_state), false}

      {:error, reason} ->
        {error_reply(message, error_reason(reason)), state, false}
    end
  end

  defp handle(message, state, _config) do
    {error_reply(message, "unsupported_message_type"), state, false}
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

  defp ok_reply(message, payload) do
    %{
      "status" => "ok",
      "message_type" => message["message_type"],
      "protocol_version" => message["protocol_version"],
      "session_ref" => message["session_ref"],
      "trace_id" => message["trace_id"],
      "payload" => payload
    }
  end

  defp error_reply(message, error) do
    %{
      "status" => "error",
      "message_type" => message["message_type"],
      "protocol_version" => message["protocol_version"],
      "session_ref" => message["session_ref"],
      "trace_id" => message["trace_id"],
      "error" => error
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp handler(config), do: Map.fetch!(config, :handler)

  defp error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_reason(reason) when is_binary(reason), do: reason
  defp error_reason(reason), do: inspect(reason)
end
