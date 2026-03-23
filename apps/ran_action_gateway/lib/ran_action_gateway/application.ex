defmodule RanActionGateway.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RanActionGateway.ChangeSupervisor,
      RanActionGateway.ControlState,
      {RanActionGateway.ApprovalGate, %{}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RanActionGateway.Supervisor)
  end
end
