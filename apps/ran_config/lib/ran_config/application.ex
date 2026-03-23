defmodule RanConfig.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {RanConfig.ProfileCache,
       %{profile: Application.get_env(:ran_config, :repo_profile, :bootstrap)}}
    ]

    with {:ok, supervisor} <-
           Supervisor.start_link(children, strategy: :one_for_one, name: RanConfig.Supervisor),
         :ok <- maybe_load_topology() do
      {:ok, supervisor}
    end
  end

  defp maybe_load_topology do
    case RanConfig.load_topology_from_env() do
      :ok -> :ok
      {:ok, _report} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
