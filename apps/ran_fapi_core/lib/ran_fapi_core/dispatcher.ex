defmodule RanFapiCore.Dispatcher do
  @moduledoc """
  Contract-only southbound dispatcher for bootstrap work.

  It turns normalized scheduler output into canonical IR and hands it to the
  selected backend profile without introducing live transport loops.
  """

  alias RanFapiCore.{Capability, IR, Profile}
  alias RanSchedulerHost.SlotPlan

  @spec build_ir(RanCore.cell_group_id(), RanCore.backend_profile(), SlotPlan.t(), keyword()) ::
          IR.t()
  def build_ir(cell_group_id, profile, %SlotPlan{} = slot_plan, opts \\ []) do
    %IR{
      cell_group_id: cell_group_id,
      ue_ref: Keyword.get(opts, :ue_ref) || fetch_ue_ref(slot_plan.metadata),
      frame: slot_plan.slot_ref.frame,
      slot: slot_plan.slot_ref.slot,
      profile: profile,
      messages: slot_plan.fapi_messages,
      metadata:
        Map.merge(slot_plan.metadata, %{
          scheduler: slot_plan.scheduler,
          status: slot_plan.status
        })
    }
  end

  @spec dispatch_slot(RanCore.cell_group_id(), RanCore.backend_profile(), SlotPlan.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def dispatch_slot(cell_group_id, profile, %SlotPlan{} = slot_plan, opts \\ []) do
    with {:ok, backend} <- Profile.backend_module(profile),
         {:ok, capability} <- Profile.capabilities(profile),
         ir <- build_ir(cell_group_id, profile, slot_plan, opts),
         :ok <- IR.validate(ir),
         :ok <- Capability.compatible?(capability, profile, IR.message_kinds(ir)),
         {:ok, session} <- backend.open_session(dispatch_opts(cell_group_id, profile, opts)),
         :ok <- backend.activate_cell(session, cell_group_id: cell_group_id),
         :ok <- backend.submit_slot(session, ir),
         {:ok, health} <- backend.health(session),
         :ok <- backend.terminate(session) do
      {:ok,
       %{
         status: :submitted,
         backend: profile,
         cell_group_id: cell_group_id,
         health: health,
         slot_plan: slot_plan,
         ir: ir,
         backend_capabilities: capability
       }}
    end
  end

  defp dispatch_opts(cell_group_id, profile, opts) do
    [
      cell_group_id: cell_group_id,
      profile: profile,
      dispatch_mode: :bootstrap
    ] ++ opts
  end

  defp fetch_ue_ref(metadata) when is_map(metadata) do
    metadata[:ue_ref] || metadata["ue_ref"]
  end
end
