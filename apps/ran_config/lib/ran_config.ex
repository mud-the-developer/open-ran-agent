defmodule RanConfig do
  @moduledoc """
  Bootstrap environment and topology profile loader.
  """

  alias RanConfig.{ChangePolicy, ReleaseCheck, TopologyLoader, Validator}

  @spec current_profile() :: atom()
  def current_profile do
    fallback = Application.get_env(:ran_config, :repo_profile, :bootstrap)
    cached_value(:profile, fallback)
  end

  @spec cell_groups() :: [map()]
  def cell_groups do
    Application.get_env(:ran_config, :cell_groups, [])
  end

  @spec topology_source() :: String.t() | nil
  def topology_source do
    cached_value(:topology_source, Application.get_env(:ran_config, :topology_source))
  end

  @spec find_cell_group(String.t()) :: {:ok, map()} | {:error, :not_found}
  def find_cell_group(cell_group_id) do
    case Enum.find(cell_groups(), &(&1[:id] == cell_group_id || &1["id"] == cell_group_id)) do
      nil -> {:error, :not_found}
      cell_group -> {:ok, cell_group}
    end
  end

  @spec validation_report(keyword()) :: map()
  def validation_report(env \\ Application.get_all_env(:ran_config)) do
    env
    |> Validator.validate_env()
    |> Map.put(:topology_source, Keyword.get(env, :topology_source, topology_source()))
  end

  @spec backend_switch_policy(String.t(), atom() | nil) :: {:ok, map()} | {:error, map()}
  def backend_switch_policy(cell_group_id, target_backend \\ nil) do
    ChangePolicy.switch_policy(cell_group_id, target_backend)
  end

  @spec release_readiness(keyword()) :: map()
  def release_readiness(env \\ Application.get_all_env(:ran_config)) do
    ReleaseCheck.check_env(env)
  end

  @spec load_topology(Path.t()) :: {:ok, map()} | {:error, map()}
  def load_topology(path) when is_binary(path) do
    with {:ok, env} <- TopologyLoader.load_file(path),
         report <- Validator.validate_env(env),
         :ok <- ensure_valid_topology(report, path) do
      Enum.each(env, fn {key, value} ->
        Application.put_env(:ran_config, key, value, persistent: true)
      end)

      maybe_cache(:profile, Keyword.get(env, :repo_profile, :bootstrap))
      maybe_cache(:topology_source, Keyword.get(env, :topology_source))

      {:ok, Map.put(report, :topology_source, Path.expand(path))}
    end
  end

  @spec load_topology_from_env() :: :ok | {:ok, map()} | {:error, map()}
  def load_topology_from_env do
    case System.get_env("RAN_TOPOLOGY_FILE") || Application.get_env(:ran_config, :topology_file) do
      nil -> :ok
      path -> load_topology(path)
    end
  end

  defp ensure_valid_topology(%{status: :ok}, _path), do: :ok

  defp ensure_valid_topology(report, path) do
    {:error,
     %{status: "invalid_topology", path: Path.expand(path), errors: report.errors, report: report}}
  end

  defp cached_value(key, default) do
    case Process.whereis(RanConfig.ProfileCache) do
      nil -> default
      _pid -> RanConfig.ProfileCache.get(key, default)
    end
  end

  defp maybe_cache(_key, nil), do: :ok

  defp maybe_cache(key, value) do
    case Process.whereis(RanConfig.ProfileCache) do
      nil -> :ok
      _pid -> RanConfig.ProfileCache.put(key, value)
    end
  end
end
