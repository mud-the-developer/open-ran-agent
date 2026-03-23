defmodule RanFapiCore.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: RanFapiCore.ProfileRegistry},
      RanFapiCore.GatewaySessionSupervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RanFapiCore.Supervisor)
  end
end
