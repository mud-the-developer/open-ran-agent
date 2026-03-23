defmodule RanDuHigh do
  @moduledoc """
  DU-high boundary. Owns cell-group lifecycle and delegates scheduling and southbound
  work to dedicated applications.
  """

  alias RanDuHigh.CellGroup
  alias RanSchedulerHost.SlotPlan

  @spec new_cell_group(String.t(), keyword()) :: CellGroup.t()
  def new_cell_group(cell_group_id, opts \\ []) do
    %CellGroup{
      id: cell_group_id,
      backend: Keyword.get(opts, :backend, :stub_fapi_profile),
      scheduler: Keyword.get(opts, :scheduler, :cpu_scheduler)
    }
  end

  @spec plan_slot(CellGroup.t(), map(), keyword()) :: {:ok, SlotPlan.t()} | {:error, term()}
  def plan_slot(%CellGroup{} = cell_group, slot_context, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, scheduler_module(cell_group.scheduler))
    slot_plan = RanSchedulerHost.plan_slot(slot_context, adapter: adapter)

    case slot_plan.status do
      :planned -> {:ok, slot_plan}
      status -> {:error, {:scheduler_not_ready, status}}
    end
  end

  @spec run_slot(CellGroup.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_slot(%CellGroup{} = cell_group, slot_context, opts \\ []) do
    with {:ok, slot_plan} <- plan_slot(cell_group, slot_context, opts) do
      RanFapiCore.dispatch_slot(cell_group.id, cell_group.backend, slot_plan, opts)
    end
  end

  @spec scheduler_module(atom()) :: module()
  def scheduler_module(scheduler), do: RanSchedulerHost.resolve_adapter(scheduler)
end
