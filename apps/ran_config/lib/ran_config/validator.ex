defmodule RanConfig.Validator do
  @moduledoc """
  Validates bootstrap topology and scheduler/backend declarations.
  """

  @supported_backends [:stub_fapi_profile, :local_fapi_profile, :aerial_fapi_profile]
  @supported_schedulers [:cpu_scheduler, :cumac_scheduler]

  @spec supported_backends() :: [atom()]
  def supported_backends, do: @supported_backends

  @spec supported_schedulers() :: [atom()]
  def supported_schedulers, do: @supported_schedulers

  @spec validate_env(keyword()) :: map()
  def validate_env(env) do
    cell_groups = Keyword.get(env, :cell_groups, [])
    profile = Keyword.get(env, :profile, Keyword.get(env, :repo_profile, :bootstrap))
    default_backend = Keyword.get(env, :default_backend, :stub_fapi_profile)
    scheduler_adapter = Keyword.get(env, :scheduler_adapter, :cpu_scheduler)

    errors =
      []
      |> validate_profile(profile)
      |> validate_default_backend(default_backend)
      |> validate_scheduler_adapter(scheduler_adapter)
      |> validate_cell_groups(cell_groups)

    %{
      status: if(errors == [], do: :ok, else: :error),
      profile: profile,
      default_backend: default_backend,
      scheduler_adapter: scheduler_adapter,
      cell_group_count: length(cell_groups),
      supported_backends: @supported_backends,
      supported_schedulers: @supported_schedulers,
      errors: Enum.reverse(errors) |> Enum.map(&format_error/1)
    }
  end

  defp validate_profile(errors, profile) when is_atom(profile), do: errors
  defp validate_profile(errors, _profile), do: [{:profile, "must be an atom"} | errors]

  defp validate_default_backend(errors, backend) when backend in @supported_backends, do: errors

  defp validate_default_backend(errors, _backend) do
    [{:default_backend, "must be a supported backend"} | errors]
  end

  defp validate_scheduler_adapter(errors, scheduler) when scheduler in @supported_schedulers,
    do: errors

  defp validate_scheduler_adapter(errors, _scheduler) do
    [{:scheduler_adapter, "must be a supported scheduler"} | errors]
  end

  defp validate_cell_groups(errors, cell_groups)
       when is_list(cell_groups) and cell_groups != [] do
    cell_group_ids =
      Enum.map(cell_groups, fn cell_group ->
        cell_group[:id] || cell_group["id"]
      end)

    errors
    |> validate_unique_ids(cell_group_ids)
    |> then(fn current_errors ->
      Enum.reduce(cell_groups, current_errors, fn cell_group, acc ->
        validate_cell_group(acc, cell_group)
      end)
    end)
  end

  defp validate_cell_groups(errors, []), do: [{:cell_groups, "must not be empty"} | errors]
  defp validate_cell_groups(errors, _), do: [{:cell_groups, "must be a list"} | errors]

  defp validate_unique_ids(errors, ids) do
    if Enum.uniq(ids) == ids do
      errors
    else
      [{:cell_groups, "ids must be unique"} | errors]
    end
  end

  defp validate_cell_group(errors, cell_group) do
    id = cell_group[:id] || cell_group["id"]
    du = cell_group[:du] || cell_group["du"]
    backend = cell_group[:backend] || cell_group["backend"]
    scheduler = cell_group[:scheduler] || cell_group["scheduler"]
    failover_targets = cell_group[:failover_targets] || cell_group["failover_targets"] || []

    errors
    |> require_cell_group_field(:id, id)
    |> require_cell_group_field(:du, du)
    |> validate_cell_group_backend(id, backend)
    |> validate_cell_group_scheduler(id, scheduler)
    |> validate_failover_targets(failover_targets)
  end

  defp require_cell_group_field(errors, _field, value) when value not in [nil, ""], do: errors

  defp require_cell_group_field(errors, field, _value),
    do: [{:cell_group, "#{field} is required"} | errors]

  defp validate_cell_group_backend(errors, _id, backend) when backend in @supported_backends,
    do: errors

  defp validate_cell_group_backend(errors, id, _backend),
    do: [{:cell_group, "#{id || "unknown"} backend must be supported"} | errors]

  defp validate_cell_group_scheduler(errors, _id, scheduler)
       when scheduler in @supported_schedulers,
       do: errors

  defp validate_cell_group_scheduler(errors, id, _scheduler),
    do: [{:cell_group, "#{id || "unknown"} scheduler must be supported"} | errors]

  defp validate_failover_targets(errors, targets) when is_list(targets) do
    if Enum.all?(targets, &(&1 in @supported_backends)) do
      errors
    else
      [{:cell_group, "failover_targets must contain only supported backends"} | errors]
    end
  end

  defp validate_failover_targets(errors, _targets),
    do: [{:cell_group, "failover_targets must be a list"} | errors]

  defp format_error({field, message}) do
    %{
      field: Atom.to_string(field),
      message: message
    }
  end
end
