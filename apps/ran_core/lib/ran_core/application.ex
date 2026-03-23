defmodule RanCore.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: RanCore.NodeRegistry},
      {Registry, keys: :unique, name: RanCore.ChangeRegistry},
      {RanCore.Topology, %{}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RanCore.Supervisor)
  end
end
