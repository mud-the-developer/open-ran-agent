defmodule RanFapiCore.Backends.StubBackend do
  @moduledoc """
  Contract-validation backend used before any live southbound transport exists.
  """

  alias RanFapiCore.{Capability, Health, PortGatewayClient}

  @behaviour RanFapiCore.Backends.Adapter

  @impl true
  def capabilities do
    Capability.normalize!(%{
      profile: :stub_fapi_profile,
      supported_message_kinds:
        RanFapiCore.IR.message_kinds(%RanFapiCore.IR{
          cell_group_id: "cg-bootstrap",
          frame: 0,
          slot: 0,
          profile: :stub_fapi_profile,
          messages: [
            %{kind: :dl_tti_request, payload: %{}},
            %{kind: :tx_data_request, payload: %{}},
            %{kind: :ul_tti_request, payload: %{}},
            %{kind: :ul_dci_request, payload: %{}},
            %{kind: :slot_indication, payload: %{}},
            %{kind: :rx_data_indication, payload: %{}}
          ]
        }),
      max_cell_groups: 1,
      timing_model: :slot_batch,
      drain_support: true,
      rollback_support: true,
      artifact_capture_support: true,
      status: :bootstrap
    })
  end

  @impl true
  def open_session(opts) do
    if Keyword.get(opts, :transport) == :port do
      PortGatewayClient.open(opts)
    else
      {:ok, %{profile: :stub_fapi_profile, opts: opts}}
    end
  end

  @impl true
  def activate_cell(%{mode: :port} = session, opts),
    do: PortGatewayClient.activate_cell(session, opts)

  def activate_cell(_session, _opts), do: :ok

  @impl true
  def submit_slot(%{mode: :port} = session, ir), do: PortGatewayClient.submit_slot(session, ir)
  def submit_slot(_session, _ir), do: :ok

  @impl true
  def handle_uplink_indication(%{mode: :port} = session, indication),
    do: PortGatewayClient.handle_uplink_indication(session, indication)

  def handle_uplink_indication(_session, _indication), do: :ok

  @impl true
  def health(%{mode: :port} = session), do: PortGatewayClient.health(session)
  def health(_session), do: {:ok, Health.new(:healthy, session_status: :active)}

  @impl true
  def quiesce(%{mode: :port} = session, opts), do: PortGatewayClient.quiesce(session, opts)
  def quiesce(_session, _opts), do: :ok

  @impl true
  def resume(%{mode: :port} = session), do: PortGatewayClient.resume(session)
  def resume(_session), do: :ok

  @impl true
  def terminate(%{mode: :port} = session), do: PortGatewayClient.terminate(session)
  def terminate(_session), do: :ok
end
