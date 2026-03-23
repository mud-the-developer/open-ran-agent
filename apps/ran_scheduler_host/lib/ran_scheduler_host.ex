defmodule RanSchedulerHost do
  @moduledoc """
  Scheduler host boundary. Keeps scheduler implementations swappable.
  """

  alias RanSchedulerHost.{CpuScheduler, CumacScheduler, SlotPlan}

  @spec plan_slot(map(), keyword()) :: SlotPlan.t()
  def plan_slot(slot_context, opts \\ []) do
    scheduler =
      opts
      |> Keyword.get(:adapter, CpuScheduler)
      |> resolve_adapter()

    scheduler.plan_slot(slot_context, opts)
  end

  @spec resolve_adapter(atom() | module()) :: module()
  def resolve_adapter(:cpu_scheduler), do: CpuScheduler
  def resolve_adapter(:cumac_scheduler), do: CumacScheduler
  def resolve_adapter(module) when is_atom(module), do: module
end
