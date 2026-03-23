defmodule RanCuUp.TunnelSupervisor do
  @moduledoc """
  Supervises tunnel-scoped workers so CU-UP tunnel faults stay local.
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
