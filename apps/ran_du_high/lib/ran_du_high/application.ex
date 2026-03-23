defmodule RanDuHigh.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RanDuHigh.CellGroupSupervisor,
      {Task.Supervisor, name: RanDuHigh.BackendDrainCoordinator}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RanDuHigh.Supervisor)
  end
end
