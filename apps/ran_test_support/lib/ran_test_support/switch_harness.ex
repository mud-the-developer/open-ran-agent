defmodule RanTestSupport.SwitchHarness do
  @moduledoc """
  Reusable integration harness for controlled backend switch and rollback paths.
  """

  alias RanActionGateway.{Request, Runner, Store}

  @type phase_result :: {:ok, map()} | {:error, map()}

  @spec run_sequence(map(), [atom()]) :: {:ok, map()} | {:error, map()}
  def run_sequence(payload, commands \\ [:precheck, :plan, :apply, :verify, :rollback]) do
    with {:ok, change} <- Request.build_change(payload) do
      execute_commands(change, commands, %{})
    end
  end

  @spec artifact_refs(String.t(), String.t() | nil) :: map()
  def artifact_refs(change_id, incident_id \\ nil) do
    %{
      plan: Store.plan_path(change_id),
      change_state: Store.change_state_path(change_id),
      verify: Store.verify_path(change_id),
      rollback_plan: Store.rollback_plan_path(change_id),
      apply_approval: Store.approval_path(change_id, "apply"),
      rollback_approval: Store.approval_path(change_id, "rollback"),
      capture:
        if(incident_id || change_id,
          do: Store.capture_path(incident_id || change_id),
          else: nil
        )
    }
  end

  defp execute_commands(_change, [], results) do
    {:ok, %{results: results}}
  end

  defp execute_commands(change, [command | rest], results) do
    case Runner.execute(command, change) do
      {:ok, result} ->
        execute_commands(change, rest, Map.put(results, command, result))

      {:error, error} ->
        {:error,
         %{
           failed_command: command,
           error: error,
           results: results
         }}
    end
  end
end
