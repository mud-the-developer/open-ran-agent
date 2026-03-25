defmodule RanActionGateway.RuntimeContract do
  @moduledoc """
  Release-aware runtime contract helpers for runtime-enabled `ranctl` commands.
  """

  alias RanActionGateway.{Change, OaiRuntime}

  @lifecycle_commands [:precheck, :plan, :apply, :verify, :rollback]
  @supported_version "ranctl.runtime.v1"
  @expected_entrypoint "bin/ranctl"
  @required_fields ~w(version release_unit release_ref entrypoint runtime_mode)

  @spec supported_version() :: String.t()
  def supported_version, do: @supported_version

  @spec expected_entrypoint() :: String.t()
  def expected_entrypoint, do: @expected_entrypoint

  @spec validate([tuple()], atom(), Change.t()) :: [tuple()]
  def validate(errors, command, %Change{} = change) when command in @lifecycle_commands do
    if runtime_requested?(change) do
      contract = request_contract(change)

      errors
      |> validate_contract_present(contract)
      |> validate_required_fields(contract)
      |> validate_version(contract)
      |> validate_release_unit(contract)
      |> validate_entrypoint(contract)
    else
      errors
    end
  end

  def validate(errors, _command, _change), do: errors

  @spec precheck_contract(Change.t()) :: {:ok, map() | nil} | {:error, map()}
  def precheck_contract(%Change{} = change) do
    if runtime_requested?(change) do
      build_contract(change)
    else
      {:ok, nil}
    end
  end

  @spec plan_contract(Change.t()) :: {:ok, map() | nil} | {:error, map()}
  def plan_contract(%Change{} = change) do
    if runtime_requested?(change) do
      build_contract(change)
    else
      {:ok, nil}
    end
  end

  @spec ensure_planned_contract(atom(), Change.t(), map()) :: {:ok, map() | nil} | {:error, map()}
  def ensure_planned_contract(command, %Change{} = change, plan)
      when command in [:apply, :verify, :rollback] and is_map(plan) do
    planned_contract = plan["runtime_contract"]

    cond do
      is_nil(planned_contract) and runtime_requested?(change) ->
        {:error,
         %{
           status: "missing_runtime_contract",
           command: command_to_string(command),
           errors: ["plan artifact is missing runtime_contract for this runtime-enabled change"]
         }}

      is_nil(planned_contract) ->
        {:ok, nil}

      not runtime_requested?(change) ->
        {:error,
         %{
           status: "missing_runtime_contract",
           command: command_to_string(command),
           errors: [
             "metadata.oai_runtime and metadata.runtime_contract are required for #{command_to_string(command)} after a runtime-enabled plan"
           ]
         }}

      true ->
        with {:ok, request_contract} <- normalize_request_contract(change),
             :ok <- ensure_request_matches_plan(command, request_contract, planned_contract),
             {:ok, snapshot} <- OaiRuntime.contract_snapshot(change.cell_group, change.metadata),
             :ok <- ensure_snapshot_matches_plan(command, snapshot, planned_contract) do
          {:ok, planned_contract}
        end
    end
  end

  defp build_contract(%Change{} = change) do
    with {:ok, request_contract} <- normalize_request_contract(change),
         {:ok, snapshot} <- OaiRuntime.contract_snapshot(change.cell_group, change.metadata),
         :ok <- ensure_runtime_mode(request_contract, snapshot.runtime_mode) do
      {:ok,
       request_contract
       |> Map.put("runtime_mode", snapshot.runtime_mode)
       |> Map.put("runtime_digest", snapshot.runtime_digest)
       |> Map.put("release_readiness", release_snapshot())}
    end
  end

  defp normalize_request_contract(%Change{} = change) do
    contract =
      change
      |> request_contract()
      |> stringify_keys()
      |> Map.take(@required_fields)

    missing =
      Enum.filter(@required_fields, fn field ->
        contract[field] in [nil, ""]
      end)

    cond do
      missing != [] ->
        {:error,
         %{
           status: "missing_runtime_contract",
           errors: [
             "metadata.runtime_contract must include #{Enum.join(missing, ", ")}"
           ]
         }}

      contract["version"] != @supported_version ->
        {:error,
         %{
           status: "unsupported_runtime_contract",
           errors: ["runtime_contract.version must be #{@supported_version}"]
         }}

      contract["release_unit"] != expected_release_unit() ->
        {:error,
         %{
           status: "runtime_contract_mismatch",
           errors: [
             "runtime_contract.release_unit must be #{expected_release_unit()} for this entrypoint"
           ]
         }}

      contract["entrypoint"] != @expected_entrypoint ->
        {:error,
         %{
           status: "runtime_contract_mismatch",
           errors: ["runtime_contract.entrypoint must be #{@expected_entrypoint}"]
         }}

      true ->
        {:ok, contract}
    end
  end

  defp ensure_runtime_mode(contract, runtime_mode) do
    if contract["runtime_mode"] == runtime_mode do
      :ok
    else
      {:error,
       %{
         status: "runtime_contract_mismatch",
         errors: [
           "runtime_contract.runtime_mode=#{contract["runtime_mode"]} does not match resolved runtime mode #{runtime_mode}"
         ]
       }}
    end
  end

  defp ensure_request_matches_plan(command, request_contract, planned_contract) do
    mismatches =
      Enum.reduce(@required_fields, [], fn field, acc ->
        if request_contract[field] == planned_contract[field] do
          acc
        else
          [
            "#{field}=#{inspect(request_contract[field])} does not match planned #{inspect(planned_contract[field])}"
            | acc
          ]
        end
      end)
      |> Enum.reverse()

    case mismatches do
      [] ->
        :ok

      _ ->
        {:error,
         %{
           status: "runtime_contract_mismatch",
           command: command_to_string(command),
           errors: mismatches
         }}
    end
  end

  defp ensure_snapshot_matches_plan(command, snapshot, planned_contract) do
    mismatches =
      []
      |> maybe_add_mismatch(
        snapshot.runtime_mode != planned_contract["runtime_mode"],
        "resolved runtime_mode=#{snapshot.runtime_mode} does not match planned #{inspect(planned_contract["runtime_mode"])}"
      )
      |> maybe_add_mismatch(
        snapshot.runtime_digest != planned_contract["runtime_digest"],
        "resolved runtime_digest=#{snapshot.runtime_digest} does not match planned #{inspect(planned_contract["runtime_digest"])}"
      )

    case mismatches do
      [] ->
        :ok

      _ ->
        {:error,
         %{
           status: "runtime_contract_mismatch",
           command: command_to_string(command),
           errors: Enum.reverse(mismatches)
         }}
    end
  end

  defp validate_contract_present(errors, contract) when map_size(contract) > 0, do: errors

  defp validate_contract_present(errors, _contract) do
    [
      {:runtime_contract,
       "must be provided under metadata.runtime_contract when metadata.oai_runtime is present"}
      | errors
    ]
  end

  defp validate_required_fields(errors, contract) do
    missing =
      Enum.filter(@required_fields, fn field ->
        contract[field] in [nil, ""]
      end)

    if missing == [] do
      errors
    else
      [
        {:runtime_contract,
         "must include #{Enum.join(@required_fields, ", ")} for runtime-enabled lifecycle commands"}
        | errors
      ]
    end
  end

  defp validate_version(errors, %{"version" => @supported_version}), do: errors
  defp validate_version(errors, %{"version" => nil}), do: errors
  defp validate_version(errors, %{"version" => ""}), do: errors

  defp validate_version(errors, _contract) do
    [{:runtime_contract, "version must be #{@supported_version}"} | errors]
  end

  defp validate_release_unit(errors, %{"release_unit" => unit}) when unit in [nil, ""], do: errors

  defp validate_release_unit(errors, %{"release_unit" => unit}) do
    if unit == expected_release_unit() do
      errors
    else
      [{:runtime_contract, "release_unit must be #{expected_release_unit()}"} | errors]
    end
  end

  defp validate_release_unit(errors, _contract), do: errors

  defp validate_entrypoint(errors, %{"entrypoint" => entrypoint})
       when entrypoint in [nil, ""],
       do: errors

  defp validate_entrypoint(errors, %{"entrypoint" => @expected_entrypoint}), do: errors

  defp validate_entrypoint(errors, _contract) do
    [{:runtime_contract, "entrypoint must be #{@expected_entrypoint}"} | errors]
  end

  defp request_contract(%Change{metadata: metadata}) when is_map(metadata) do
    metadata
    |> Map.get("runtime_contract", Map.get(metadata, :runtime_contract, %{}))
    |> stringify_keys()
  end

  defp request_contract(_change), do: %{}

  defp runtime_requested?(%Change{metadata: metadata}) when is_map(metadata),
    do: OaiRuntime.runtime_requested?(metadata)

  defp runtime_requested?(_change), do: false

  defp release_snapshot do
    report = RanConfig.release_readiness()

    %{
      "status" => maybe_to_string(report.status),
      "release_unit" => maybe_to_string(report.release_unit),
      "profile" => maybe_to_string(report.profile),
      "topology_source" => report.topology_source,
      "checks" => Map.get(report, :checks, []),
      "errors" => Map.get(report, :errors, [])
    }
  end

  defp expected_release_unit do
    release_snapshot()["release_unit"]
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_keys(_value), do: %{}

  defp maybe_add_mismatch(errors, true, error), do: [error | errors]
  defp maybe_add_mismatch(errors, false, _error), do: errors

  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value), do: value

  defp command_to_string(command), do: command |> Atom.to_string() |> String.replace("_", "-")
end
