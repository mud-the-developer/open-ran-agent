defmodule RanActionGateway.WizardBoot do
  @moduledoc """
  Loads repository config files before entering the deployment wizard.
  """

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    load_repo_config!("config/config.exs")
    load_repo_config!("config/runtime.exs")

    with :ok <- ensure_runtime_apps(),
         :ok <- maybe_load_topology() do
      RanActionGateway.DeployWizard.main(argv)
    else
      {:error, payload} ->
        IO.puts(JSON.encode!(payload))
        System.halt(1)
    end
  end

  defp load_repo_config!(path) do
    path
    |> Config.Reader.read!()
    |> Enum.each(fn {app, env} ->
      Enum.each(env, fn {key, value} ->
        Application.put_env(app, key, value, persistent: true)
      end)
    end)
  end

  defp ensure_runtime_apps do
    case Application.ensure_all_started(:ran_action_gateway) do
      {:ok, _started} ->
        :ok

      {:error, reason} ->
        {:error, %{status: "startup_failed", errors: [inspect(reason)]}}
    end
  end

  defp maybe_load_topology do
    case RanConfig.load_topology_from_env() do
      :ok -> :ok
      {:ok, _report} -> :ok
      {:error, payload} -> {:error, payload}
    end
  end
end
