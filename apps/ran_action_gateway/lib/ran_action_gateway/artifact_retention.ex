defmodule RanActionGateway.ArtifactRetention do
  @moduledoc """
  Deterministic retention planner and explicit prune action for bootstrap artifacts.
  """

  alias RanActionGateway.Store

  @spec default_policy() :: map()
  def default_policy do
    %{
      json_keep: 20,
      runtime_keep: 8,
      release_keep: 5,
      protect_control_state: true
    }
  end

  @spec plan(keyword()) :: map()
  def plan(opts \\ []) do
    artifact_root = artifact_root(opts)
    policy = policy(opts)

    json_decisions =
      Store.json_artifact_kinds()
      |> Enum.flat_map(&json_decisions(artifact_root, &1, policy.json_keep))

    runtime_decisions = directory_decisions(artifact_root, "runtime", policy.runtime_keep)
    release_decisions = directory_decisions(artifact_root, "releases", policy.release_keep)

    protected =
      if policy.protect_control_state do
        protected_directory_entries(artifact_root, "control_state")
      else
        []
      end

    decisions = json_decisions ++ runtime_decisions ++ release_decisions

    %{
      status: "planned",
      artifact_root: artifact_root,
      policy: policy,
      summary: summarize(decisions, protected),
      prune: Enum.filter(decisions, &(&1.action == "prune")),
      keep: Enum.filter(decisions, &(&1.action == "keep")),
      protected: protected
    }
  end

  @spec apply(keyword()) :: {:ok, map()} | {:error, map()}
  def apply(opts \\ []) do
    plan = plan(opts)

    with :ok <- ensure_safe_paths(plan.prune, plan.artifact_root) do
      Enum.each(plan.prune, &delete_entry!/1)

      {:ok,
       %{
         plan
         | status: "pruned",
           summary: Map.put(plan.summary, :pruned_count, length(plan.prune))
       }}
    else
      {:error, reason} ->
        {:error, %{status: "unsafe_prune", errors: [inspect(reason)], plan: plan}}
    end
  end

  defp json_decisions(artifact_root, kind, keep_limit) do
    [artifact_root, kind, "*.json"]
    |> Path.join()
    |> Path.wildcard()
    |> file_entries(kind)
    |> rank_entries()
    |> mark_decisions(keep_limit)
  end

  defp directory_decisions(artifact_root, kind, keep_limit) do
    [artifact_root, kind, "*"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&directory_entry(kind, &1))
    |> rank_entries()
    |> mark_decisions(keep_limit)
  end

  defp protected_directory_entries(artifact_root, kind) do
    [artifact_root, kind, "*"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.map(fn path ->
      %{
        category: kind,
        path: Path.expand(path),
        entry_type: entry_type(path),
        action: "protected",
        updated_at: updated_at_string(path)
      }
    end)
  end

  defp file_entries(paths, kind) do
    Enum.map(paths, fn path ->
      %{
        category: kind,
        path: Path.expand(path),
        entry_type: "file",
        updated_at: updated_at_string(path),
        updated_at_unix: updated_at_unix(path)
      }
    end)
  end

  defp directory_entry(kind, path) do
    %{
      category: kind,
      path: Path.expand(path),
      entry_type: entry_type(path),
      updated_at: updated_at_string(path),
      updated_at_unix: updated_at_unix(path)
    }
  end

  defp rank_entries(entries) do
    Enum.sort_by(entries, & &1.updated_at_unix, :desc)
  end

  defp mark_decisions(entries, keep_limit) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      action = if index < keep_limit, do: "keep", else: "prune"
      Map.drop(entry, [:updated_at_unix]) |> Map.put(:action, action)
    end)
  end

  defp summarize(decisions, protected) do
    %{
      prune_count: Enum.count(decisions, &(&1.action == "prune")),
      keep_count: Enum.count(decisions, &(&1.action == "keep")),
      protected_count: length(protected)
    }
  end

  defp delete_entry!(%{path: path, entry_type: "file"}), do: File.rm!(path)
  defp delete_entry!(%{path: path}), do: File.rm_rf!(path)

  defp ensure_safe_paths(entries, artifact_root) do
    unsafe =
      Enum.find(entries, fn %{path: path} ->
        relative = Path.relative_to(path, artifact_root)
        relative == path or String.starts_with?(relative, "..")
      end)

    if unsafe do
      {:error, {:outside_artifact_root, unsafe.path}}
    else
      :ok
    end
  end

  defp artifact_root(opts) do
    opts
    |> Keyword.get(:artifact_root, Store.artifact_root())
    |> Path.expand()
  end

  defp policy(opts) do
    base = default_policy()

    %{
      json_keep: Keyword.get(opts, :json_keep, base.json_keep),
      runtime_keep: Keyword.get(opts, :runtime_keep, base.runtime_keep),
      release_keep: Keyword.get(opts, :release_keep, base.release_keep),
      protect_control_state: Keyword.get(opts, :protect_control_state, base.protect_control_state)
    }
  end

  defp updated_at_string(path) do
    path
    |> updated_at_datetime()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp updated_at_unix(path) do
    path
    |> updated_at_datetime()
    |> DateTime.to_unix()
  end

  defp updated_at_datetime(path) do
    path
    |> candidate_paths()
    |> Enum.map(&safe_stat/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix/1, fn -> epoch_datetime() end)
  end

  defp entry_type(path) do
    if File.dir?(path), do: "directory", else: "file"
  end

  defp candidate_paths(path) do
    if File.dir?(path) do
      [path | Path.wildcard(Path.join(path, "**/*"))]
    else
      [path]
    end
  end

  defp safe_stat(path) do
    case File.stat(path) do
      {:ok, stat} ->
        stat.mtime
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")

      _ ->
        nil
    end
  end

  defp epoch_datetime do
    DateTime.from_naive!(~N[1970-01-01 00:00:00], "Etc/UTC")
  end
end
