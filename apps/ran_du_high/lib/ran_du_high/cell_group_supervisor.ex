defmodule RanDuHigh.CellGroupSupervisor do
  @moduledoc """
  Supervises cell-group specific workers so one cell-group can drain or restart without
  taking down unrelated state.
  """

  use DynamicSupervisor

  def start_link(arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
