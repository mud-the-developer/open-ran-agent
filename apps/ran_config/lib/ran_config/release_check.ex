defmodule RanConfig.ReleaseCheck do
  @moduledoc """
  Release-time sanity checks for controlled failover packaging.
  """

  alias RanConfig.Validator

  @release_unit :bootstrap_source_bundle

  @spec check_env(keyword()) :: map()
  def check_env(env) do
    validation = Validator.validate_env(env)
    cell_groups = Keyword.get(env, :cell_groups, [])

    release_errors =
      if validation.status == :ok do
        validate_release_targets(cell_groups)
      else
        []
      end

    checks = [
      check("config_valid", validation.status == :ok),
      check("controlled_failover_ready", release_errors == [])
    ]

    %{
      status: if(validation.status == :ok and release_errors == [], do: :ok, else: :error),
      release_unit: @release_unit,
      profile: validation.profile,
      default_backend: validation.default_backend,
      scheduler_adapter: validation.scheduler_adapter,
      cell_group_count: validation.cell_group_count,
      topology_source: Keyword.get(env, :topology_source),
      checks: checks,
      errors: validation.errors ++ Enum.map(Enum.reverse(release_errors), &format_error/1)
    }
  end

  defp validate_release_targets(cell_groups) do
    Enum.reduce(cell_groups, [], fn cell_group, errors ->
      id = fetch_value(cell_group, :id)
      backend = fetch_value(cell_group, :backend)
      failover_targets = fetch_value(cell_group, :failover_targets) || []

      errors
      |> validate_declared_failover_targets(id, failover_targets)
      |> validate_unique_failover_targets(id, failover_targets)
      |> validate_distinct_failover_targets(id, backend, failover_targets)
    end)
  end

  defp validate_declared_failover_targets(errors, _id, targets)
       when is_list(targets) and targets != [],
       do: errors

  defp validate_declared_failover_targets(errors, id, _targets) do
    [{:cell_group, "#{id || "unknown"} must declare at least one failover target"} | errors]
  end

  defp validate_unique_failover_targets(errors, id, targets) do
    if Enum.uniq(targets) == targets do
      errors
    else
      [{:cell_group, "#{id || "unknown"} failover_targets must be unique"} | errors]
    end
  end

  defp validate_distinct_failover_targets(errors, _id, _backend, []), do: errors

  defp validate_distinct_failover_targets(errors, _id, nil, _targets), do: errors

  defp validate_distinct_failover_targets(errors, id, backend, targets) do
    if Enum.any?(targets, &(&1 == backend)) do
      [
        {:cell_group, "#{id || "unknown"} failover_targets must exclude the current backend"}
        | errors
      ]
    else
      errors
    end
  end

  defp fetch_value(cell_group, key) do
    Map.get(cell_group, key) || Map.get(cell_group, Atom.to_string(key))
  end

  defp check(name, true), do: %{"name" => name, "status" => "passed"}
  defp check(name, false), do: %{"name" => name, "status" => "failed"}

  defp format_error({field, message}) do
    %{
      field: Atom.to_string(field),
      message: message
    }
  end
end
