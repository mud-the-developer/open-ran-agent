defmodule RanFapiCore do
  @moduledoc """
  Canonical DU-high southbound contract and backend profile registry.
  """

  alias RanFapiCore.{Dispatcher, GatewaySession, GatewaySessionSupervisor, IR, Profile}
  alias RanSchedulerHost.SlotPlan

  @spec supported_profiles() :: [atom()]
  def supported_profiles do
    Profile.all()
  end

  @spec capabilities(atom()) :: {:ok, RanFapiCore.Capability.t()} | {:error, :unsupported_profile}
  def capabilities(profile) do
    Profile.capabilities(profile)
  end

  @spec build_ir(RanCore.cell_group_id(), RanCore.backend_profile(), SlotPlan.t(), keyword()) ::
          IR.t()
  def build_ir(cell_group_id, profile, %SlotPlan{} = slot_plan, opts \\ []) do
    Dispatcher.build_ir(cell_group_id, profile, slot_plan, opts)
  end

  @spec dispatch_slot(RanCore.cell_group_id(), RanCore.backend_profile(), SlotPlan.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def dispatch_slot(cell_group_id, profile, %SlotPlan{} = slot_plan, opts \\ []) do
    Dispatcher.dispatch_slot(cell_group_id, profile, slot_plan, opts)
  end

  @spec start_gateway_session(RanCore.cell_group_id(), RanCore.backend_profile(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_gateway_session(cell_group_id, profile, opts \\ []) do
    GatewaySessionSupervisor.start_session(
      Keyword.merge(opts, cell_group_id: cell_group_id, profile: profile)
    )
  end

  @spec gateway_health(GenServer.server()) :: {:ok, RanFapiCore.Health.t()}
  def gateway_health(server), do: GatewaySession.health(server)

  @spec handle_uplink_indication(GenServer.server(), map()) :: :ok | {:error, term()}
  def handle_uplink_indication(server, indication),
    do: GatewaySession.handle_uplink_indication(server, indication)

  @spec restart_gateway_session(GenServer.server()) ::
          {:ok, RanFapiCore.Health.t()} | {:error, term()}
  def restart_gateway_session(server), do: GatewaySession.restart(server)
end
