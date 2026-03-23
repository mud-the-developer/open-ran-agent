defmodule RanConfig.TopologyLoader do
  @moduledoc """
  Loads a single-DU topology profile from a local JSON file.
  """

  @spec load_file(Path.t()) :: {:ok, keyword()} | {:error, map()}
  def load_file(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    with {:ok, body} <- File.read(expanded_path),
         {:ok, payload} <- JSON.decode(body),
         {:ok, env} <- normalize_topology(payload, expanded_path) do
      {:ok, env}
    else
      {:error, reason} when is_atom(reason) ->
        {:error,
         %{status: "topology_read_failed", path: expanded_path, errors: [inspect(reason)]}}

      {:error, %{status: _status} = payload} ->
        {:error, payload}

      {:error, reason} ->
        {:error,
         %{status: "invalid_topology_json", path: expanded_path, errors: [inspect(reason)]}}
    end
  end

  defp normalize_topology(%{} = payload, path) do
    repo_profile =
      payload["repo_profile"] ||
        payload["profile"] ||
        "bootstrap"

    env = [
      profile: normalize_atom(repo_profile),
      repo_profile: normalize_atom(repo_profile),
      default_backend: normalize_atom(payload["default_backend"] || "stub_fapi_profile"),
      scheduler_adapter: normalize_atom(payload["scheduler_adapter"] || "cpu_scheduler"),
      cell_groups: Enum.map(payload["cell_groups"] || [], &normalize_cell_group/1),
      topology_source: path
    ]

    {:ok, env}
  end

  defp normalize_topology(_payload, path) do
    {:error,
     %{status: "invalid_topology_root", path: path, errors: ["topology must be a JSON object"]}}
  end

  defp normalize_cell_group(%{} = cell_group) do
    %{
      id: cell_group["id"],
      du: cell_group["du"],
      backend: normalize_atom(cell_group["backend"]),
      failover_targets: Enum.map(cell_group["failover_targets"] || [], &normalize_atom/1),
      scheduler: normalize_atom(cell_group["scheduler"]),
      oai_runtime: normalize_oai_runtime(cell_group["oai_runtime"] || %{})
    }
  end

  defp normalize_cell_group(cell_group), do: cell_group

  defp normalize_oai_runtime(%{} = runtime) do
    runtime
    |> Enum.reduce(%{}, fn
      {"mode", value}, acc -> Map.put(acc, :mode, normalize_atom(value))
      {key, value}, acc -> Map.put(acc, normalize_atom(key), value)
    end)
  end

  defp normalize_oai_runtime(_runtime), do: %{}

  defp normalize_atom(nil), do: nil
  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_atom(value), do: value
end
