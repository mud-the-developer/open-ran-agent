defmodule RanObservability.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: RanObservability.ArtifactSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RanObservability.Supervisor)
  end
end
