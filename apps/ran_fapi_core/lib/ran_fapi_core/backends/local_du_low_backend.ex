defmodule RanFapiCore.Backends.LocalDuLowBackend do
  @moduledoc """
  Bootstrap contract adapter for the repository-owned local DU-low path.
  """

  alias RanFapiCore.Backends.PortBackedBackend

  @behaviour RanFapiCore.Backends.Adapter

  @impl true
  def capabilities do
    PortBackedBackend.capabilities(:local_fapi_profile, :local_du_low,
      metadata: %{
        adapter_owner: "repo",
        integration_boundary: "native_port_sidecar"
      }
    )
  end

  @impl true
  def open_session(opts),
    do: PortBackedBackend.open_session(:local_fapi_profile, :local_du_low, opts)

  @impl true
  def activate_cell(session, opts), do: PortBackedBackend.activate_cell(session, opts)

  @impl true
  def submit_slot(session, ir), do: PortBackedBackend.submit_slot(session, ir)

  @impl true
  def handle_uplink_indication(session, indication),
    do: PortBackedBackend.handle_uplink_indication(session, indication)

  @impl true
  def health(session), do: PortBackedBackend.health(session)

  @impl true
  def quiesce(session, opts), do: PortBackedBackend.quiesce(session, opts)

  @impl true
  def resume(session), do: PortBackedBackend.resume(session)

  @impl true
  def terminate(session), do: PortBackedBackend.terminate(session)
end
