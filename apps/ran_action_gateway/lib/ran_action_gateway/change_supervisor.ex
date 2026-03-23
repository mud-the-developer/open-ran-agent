defmodule RanActionGateway.ChangeSupervisor do
  @moduledoc """
  Supervises change workflows independently from runtime trees.
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
