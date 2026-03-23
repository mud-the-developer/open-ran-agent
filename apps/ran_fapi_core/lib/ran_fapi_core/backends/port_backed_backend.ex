defmodule RanFapiCore.Backends.PortBackedBackend do
  @moduledoc false

  alias RanFapiCore.{Capability, Health, IR, PortGatewayClient}

  @default_transport_modes [:port, :contract]

  @spec capabilities(RanCore.backend_profile(), atom(), keyword()) :: Capability.t()
  def capabilities(profile, backend_family, opts \\ []) do
    Capability.normalize!(%{
      profile: profile,
      max_cell_groups: Keyword.get(opts, :max_cell_groups, 1),
      timing_model: Keyword.get(opts, :timing_model, :slot_batch),
      drain_support: Keyword.get(opts, :drain_support, true),
      rollback_support: Keyword.get(opts, :rollback_support, true),
      artifact_capture_support: Keyword.get(opts, :artifact_capture_support, true),
      status: Keyword.get(opts, :status, :bootstrap),
      metadata:
        Map.merge(
          %{
            backend_family: Atom.to_string(backend_family),
            transport_modes:
              Enum.map(
                Keyword.get(opts, :transport_modes, @default_transport_modes),
                &to_string/1
              )
          },
          Keyword.get(opts, :metadata, %{})
        )
    })
  end

  @spec open_session(RanCore.backend_profile(), atom(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def open_session(profile, backend_family, opts) do
    transport = normalize_transport(Keyword.get(opts, :transport, :port))

    case transport do
      :port ->
        opts
        |> with_default_gateway_path(backend_family)
        |> Keyword.put(:profile, profile)
        |> PortGatewayClient.open()
        |> wrap_port_session(profile, backend_family)

      :contract ->
        {:ok,
         %{
           mode: :contract,
           transport: :contract,
           profile: profile,
           backend_family: backend_family,
           cell_group_id: Keyword.get(opts, :cell_group_id)
         }}
    end
  end

  @spec activate_cell(map(), keyword()) :: :ok | {:error, term()}
  def activate_cell(%{mode: :port} = session, opts),
    do: session |> PortGatewayClient.activate_cell(opts) |> normalize_port_result()

  def activate_cell(_session, _opts), do: :ok

  @spec submit_slot(map(), IR.t()) :: :ok | {:error, term()}
  def submit_slot(%{mode: :port} = session, %IR{} = ir),
    do: session |> PortGatewayClient.submit_slot(ir) |> normalize_port_result()

  def submit_slot(_session, %IR{}), do: :ok

  @spec handle_uplink_indication(map(), map()) :: :ok | {:error, term()}
  def handle_uplink_indication(%{mode: :port} = session, indication),
    do:
      session |> PortGatewayClient.handle_uplink_indication(indication) |> normalize_port_result()

  def handle_uplink_indication(_session, _indication), do: :ok

  @spec health(map()) :: {:ok, Health.t()} | {:error, term()}
  def health(%{mode: :port} = session) do
    with {:ok, health} <- PortGatewayClient.health(session) do
      {:ok, enrich_health(health, session)}
    end
  end

  def health(session) do
    {:ok,
     Health.new(:healthy,
       session_status: :active,
       checks: session_checks(session)
     )}
  end

  @spec quiesce(map(), keyword()) :: :ok | {:error, term()}
  def quiesce(%{mode: :port} = session, opts),
    do: session |> PortGatewayClient.quiesce(opts) |> normalize_port_result()

  def quiesce(_session, _opts), do: :ok

  @spec resume(map()) :: :ok | {:error, term()}
  def resume(%{mode: :port} = session),
    do: session |> PortGatewayClient.resume() |> normalize_port_result()

  def resume(_session), do: :ok

  @spec terminate(map()) :: :ok | {:error, term()}
  def terminate(%{mode: :port} = session),
    do: session |> PortGatewayClient.terminate() |> normalize_port_result()

  def terminate(_session), do: :ok

  defp wrap_port_session({:ok, session}, profile, backend_family) do
    {:ok,
     Map.merge(session, %{
       transport: :port,
       profile: profile,
       backend_family: backend_family
     })}
  end

  defp wrap_port_session({:error, _reason} = error, _profile, _backend_family), do: error

  defp enrich_health(%Health{} = health, session) do
    %{health | checks: Map.merge(health.checks, session_checks(session))}
  end

  defp session_checks(session) do
    %{
      "backend_family" => session.backend_family |> to_string(),
      "profile" => session.profile |> to_string(),
      "transport_mode" => Map.get(session, :transport, session.mode) |> to_string()
    }
  end

  defp normalize_transport(:port), do: :port
  defp normalize_transport("port"), do: :port
  defp normalize_transport(_), do: :contract

  defp with_default_gateway_path(opts, backend_family) do
    Keyword.put_new(opts, :gateway_path, default_gateway_path(backend_family))
  end

  defp default_gateway_path(:local_du_low) do
    Path.expand("../../../../../native/local_du_low_adapter/bin/contract_gateway", __DIR__)
  end

  defp default_gateway_path(:aerial) do
    Path.expand("../../../../../native/aerial_adapter/bin/contract_gateway", __DIR__)
  end

  defp default_gateway_path(_backend_family) do
    Path.expand("../../../../../native/fapi_rt_gateway/bin/synthetic_gateway", __DIR__)
  end

  defp normalize_port_result(:ok), do: :ok
  defp normalize_port_result({:ok, _result} = result), do: result

  defp normalize_port_result({:error, {"error", reason}}) when is_binary(reason) do
    {:error, normalize_reason(reason)}
  end

  defp normalize_port_result({:error, reason}), do: {:error, reason}

  defp normalize_reason(reason) when is_binary(reason) do
    try do
      String.to_existing_atom(reason)
    rescue
      ArgumentError -> reason
    end
  end

  defp normalize_reason(reason), do: reason
end
