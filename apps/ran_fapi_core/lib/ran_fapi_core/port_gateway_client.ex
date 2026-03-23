defmodule RanFapiCore.PortGatewayClient do
  @moduledoc """
  Thin Port client used by the stub backend to exercise the wire protocol.
  """

  alias RanFapiCore.{Health, IR, PortProtocol}

  @spec open(keyword()) :: {:ok, map()} | {:error, term()}
  def open(opts) do
    session_ref =
      Keyword.get(opts, :session_ref, "sess-#{System.unique_integer([:positive, :monotonic])}")

    session_payload = open_payload(opts)

    port =
      Port.open({:spawn_executable, gateway_path(opts)}, [
        :binary,
        :use_stdio,
        :exit_status,
        :stderr_to_stdout
      ])

    message =
      PortProtocol.new_message("open_session", %{
        "cell_group_id" => Keyword.get(opts, :cell_group_id),
        "session_ref" => session_ref,
        "trace_id" => "trace-open-#{session_ref}",
        "payload" => %{
          "profile" => to_string(Keyword.get(opts, :profile, :stub_fapi_profile)),
          "dispatch_mode" => to_string(Keyword.get(opts, :dispatch_mode, :bootstrap)),
          "session_payload" => session_payload
        }
      })

    with :ok <- send_frame(port, message),
         {:ok, reply} <- receive_frame(port),
         :ok <- expect_status(reply) do
      {:ok,
       %{
         mode: :port,
         port: port,
         session_ref: session_ref,
         cell_group_id: Keyword.get(opts, :cell_group_id),
         gateway_path: gateway_path(opts)
       }}
    end
  end

  @spec activate_cell(map(), keyword()) :: :ok | {:error, term()}
  def activate_cell(session, opts) do
    request(session, "activate_cell", %{
      "cell_group_id" => Keyword.get(opts, :cell_group_id, session.cell_group_id),
      "payload" => %{}
    })
  end

  @spec submit_slot(map(), IR.t()) :: :ok | {:error, term()}
  def submit_slot(session, %IR{} = ir) do
    request(session, "submit_slot_batch", %{
      "cell_group_id" => ir.cell_group_id,
      "payload" => %{"ir" => ir_to_wire(ir)}
    })
  end

  @spec handle_uplink_indication(map(), map()) :: :ok | {:error, term()}
  def handle_uplink_indication(session, indication) when is_map(indication) do
    request(session, "uplink_indication", %{
      "payload" => %{"indication" => stringify_keys(indication)}
    })
  end

  @spec health(map()) :: {:ok, Health.t()} | {:error, term()}
  def health(session) do
    with {:ok, reply} <- request(session, "health_check", %{}),
         %{"health" => health} <- reply["payload"] do
      {:ok, health_from_wire(health)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_health_reply}
    end
  end

  @spec quiesce(map(), keyword()) :: :ok | {:error, term()}
  def quiesce(session, opts) do
    request(session, "quiesce", %{
      "payload" => %{"reason" => Keyword.get(opts, :reason, "quiesce")}
    })
  end

  @spec resume(map()) :: :ok | {:error, term()}
  def resume(session) do
    request(session, "resume", %{})
  end

  @spec terminate(map()) :: :ok | {:error, term()}
  def terminate(session) do
    result = request(session, "terminate", %{})
    Port.close(session.port)
    result
  end

  defp request(session, message_type, attrs) do
    message =
      PortProtocol.new_message(message_type, %{
        "cell_group_id" => Map.get(attrs, "cell_group_id", session.cell_group_id),
        "session_ref" => session.session_ref,
        "trace_id" => "trace-#{message_type}-#{session.session_ref}",
        "payload" => Map.get(attrs, "payload", %{})
      })

    with :ok <- send_frame(session.port, message),
         {:ok, reply} <- receive_frame(session.port),
         :ok <- expect_status(reply) do
      if message_type == "health_check", do: {:ok, reply}, else: :ok
    end
  end

  defp send_frame(port, message) do
    case Port.command(port, PortProtocol.encode(message)) do
      true -> :ok
      false -> {:error, :port_closed}
    end
  end

  defp receive_frame(port, timeout \\ 20_000), do: receive_frame(port, "", timeout)

  defp receive_frame(port, buffer, timeout) do
    receive do
      {^port, {:data, chunk}} ->
        case PortProtocol.decode(buffer <> chunk) do
          {:ok, reply, _rest} -> {:ok, reply}
          :more -> receive_frame(port, buffer <> chunk, timeout)
          {:error, reason} -> {:error, reason}
        end

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp expect_status(%{"status" => "ok"}), do: :ok
  defp expect_status(%{"status" => status, "error" => reason}), do: {:error, {status, reason}}
  defp expect_status(_reply), do: {:error, :invalid_reply}

  defp gateway_path(opts) do
    Keyword.get(
      opts,
      :gateway_path,
      Path.expand("../../../../native/fapi_rt_gateway/bin/synthetic_gateway", __DIR__)
    )
  end

  defp open_payload(opts) do
    opts
    |> Keyword.get(:session_payload, %{})
    |> stringify_keys()
  end

  defp ir_to_wire(%IR{} = ir) do
    %{
      "ir_version" => ir.ir_version,
      "cell_group_id" => ir.cell_group_id,
      "ue_ref" => ir.ue_ref,
      "frame" => ir.frame,
      "slot" => ir.slot,
      "profile" => to_string(ir.profile),
      "messages" => Enum.map(ir.messages, &message_to_wire/1),
      "metadata" => stringify_keys(ir.metadata)
    }
  end

  defp message_to_wire(message) do
    kind = message[:kind] || message["kind"]

    %{
      "kind" => to_string(kind),
      "payload" => stringify_keys(message[:payload] || message["payload"] || %{})
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), wire_value(value)} end)
  end

  defp wire_value(value) when is_map(value), do: stringify_keys(value)
  defp wire_value(value) when is_list(value), do: Enum.map(value, &wire_value/1)
  defp wire_value(value) when is_atom(value), do: to_string(value)
  defp wire_value(value), do: value

  defp health_from_wire(health) do
    Health.new(String.to_atom(health["state"]),
      reason: health["reason"],
      session_status: String.to_atom(health["session_status"]),
      restart_count: health["restart_count"] || 0,
      checks: health["checks"] || %{}
    )
  end
end
