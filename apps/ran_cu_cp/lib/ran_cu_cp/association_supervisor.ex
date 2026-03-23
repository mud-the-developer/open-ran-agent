defmodule RanCuCp.AssociationSupervisor do
  @moduledoc """
  Supervises association-scoped workers so failures stay local to one association.
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
