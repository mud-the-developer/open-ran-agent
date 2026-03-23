defmodule RanFapiCore.Backends.AerialBackend do
  @moduledoc """
  Bootstrap clean-room contract adapter for future NVIDIA Aerial integration.

  This module intentionally exposes only the shared contract and does not model
  vendor internals.
  """

  alias RanFapiCore.Backends.PortBackedBackend

  @behaviour RanFapiCore.Backends.Adapter

  @impl true
  def capabilities do
    PortBackedBackend.capabilities(:aerial_fapi_profile, :aerial,
      metadata: %{
        integration_boundary: "clean_room_vendor_profile",
        vendor_surface: "opaque"
      }
    )
  end

  @impl true
  def open_session(opts), do: PortBackedBackend.open_session(:aerial_fapi_profile, :aerial, opts)

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
