defmodule RanSchedulerHost.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RanSchedulerHost.AdapterSupervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RanSchedulerHost.Supervisor)
  end
end
