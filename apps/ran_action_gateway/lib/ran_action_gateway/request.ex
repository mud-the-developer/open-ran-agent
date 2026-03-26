defmodule RanActionGateway.Request do
  @moduledoc """
  Shared request parsing for CLI and BEAM-side dashboard workflows.
  """

  alias RanActionGateway.Change
  alias RanActionGateway.Runner

  @replacement_backends ~w(oai_reference replacement_shadow replacement_primary)

  @spec command_from_string(String.t()) :: {:ok, atom()} | {:error, map()}
  def command_from_string("capture-artifacts"), do: {:ok, :capture_artifacts}

  def command_from_string(command) when is_binary(command) do
    case Enum.find(Runner.phases(), fn phase -> Atom.to_string(phase) == command end) do
      nil -> {:error, %{status: "unknown_command", command: command}}
      phase -> {:ok, phase}
    end
  end

  @spec build_change(map()) :: {:ok, Change.t()}
  def build_change(payload) when is_map(payload) do
    scope = fetch_string(payload, "scope")

    {:ok,
     %Change{
       scope: scope,
       target_ref: fetch_string(payload, "target_ref"),
       cell_group: fetch_string(payload, "cell_group"),
       target_backend: fetch_backend(payload, "target_backend", scope),
       current_backend: fetch_backend(payload, "current_backend", scope),
       requested_target_backend: fetch_backend_string(payload, "target_backend"),
       requested_current_backend: fetch_backend_string(payload, "current_backend"),
       rollback_target: fetch_string(payload, "rollback_target"),
       change_id: fetch_string(payload, "change_id"),
       incident_id: fetch_string(payload, "incident_id"),
       reason: fetch_string(payload, "reason"),
       idempotency_key: fetch_string(payload, "idempotency_key"),
       approval: fetch_map(payload, "approval", %{}),
       dry_run: Map.get(payload, "dry_run", false),
       ttl: fetch_string(payload, "ttl") || "15m",
       verify_window: fetch_map(payload, "verify_window", %{"duration" => "30s", "checks" => []}),
       max_blast_radius: fetch_string(payload, "max_blast_radius") || "single_cell_group",
       metadata: fetch_map(payload, "metadata", %{})
     }}
  end

  defp fetch_string(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp fetch_backend(payload, key, scope) do
    case Map.get(payload, key) do
      nil ->
        nil

      value when is_atom(value) ->
        cond do
          value in RanCore.supported_backends() ->
            value

          replacement_scope?(scope) and Atom.to_string(value) in @replacement_backends ->
            Atom.to_string(value)

          true ->
            nil
        end

      value when is_binary(value) ->
        cond do
          replacement_scope?(scope) and value in @replacement_backends ->
            value

          true ->
            Enum.find(RanCore.supported_backends(), fn backend ->
              Atom.to_string(backend) == value
            end)
        end

      _ ->
        nil
    end
  end

  defp fetch_backend_string(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp replacement_scope?(scope), do: scope in Runner.replacement_scopes()

  defp fetch_map(payload, key, default) do
    case Map.get(payload, key, default) do
      value when is_map(value) -> value
      _ -> default
    end
  end
end
