defmodule RanObservability.Dashboard.ActionRunner do
  @moduledoc """
  Bridges dashboard actions into the shared `ranctl` contract.
  """

  alias RanObservability.CommandRunner

  @spec run(map()) :: {:ok, map()} | {:error, map()}
  def run(payload) when is_map(payload) do
    with {:ok, command} <- fetch_command(payload),
         encoded <- JSON.encode!(Map.put(payload, "command", command)),
         {:ok, {output, exit_code}} <-
           run_ranctl([command, "--json", encoded]),
         {:ok, result} <- decode_result(output),
         :ok <- ensure_exit_status(exit_code, result) do
      {:ok, %{status: "ok", command: command, executed_at: now_iso8601(), result: result}}
    end
  end

  defp fetch_command(%{"command" => command}) when is_binary(command), do: {:ok, command}

  defp fetch_command(%{command: command}) when is_binary(command), do: {:ok, command}

  defp fetch_command(%{command: command}) when is_atom(command) do
    {:ok, command |> Atom.to_string() |> String.replace("_", "-")}
  end

  defp fetch_command(_payload) do
    {:error, %{status: "invalid_dashboard_action", errors: ["command is required"]}}
  end

  defp runner do
    Application.get_env(:ran_observability, :dashboard_command_runner, CommandRunner)
  end

  defp run_ranctl(args) do
    {:ok, runner().run(ranctl_path(), args, [])}
  rescue
    error in ErlangError ->
      {:error,
       %{
         status: "dashboard_action_exec_failed",
         errors: [Exception.message(error)],
         command: ranctl_path()
       }}
  end

  defp ranctl_path do
    Path.expand("../../../../../bin/ranctl", __DIR__)
  end

  defp decode_result(output) do
    case decode_json_candidates(output) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, reason} ->
        {:error, %{status: "invalid_action_response", errors: [inspect(reason)]}}
    end
  end

  defp decode_json_candidates(output) do
    output
    |> json_candidates()
    |> Enum.find_value(fn candidate ->
      case JSON.decode(candidate) do
        {:ok, payload} -> {:ok, payload}
        {:error, _reason} -> nil
      end
    end)
    |> case do
      nil -> JSON.decode(output)
      result -> result
    end
  end

  defp json_candidates(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reverse()
  end

  defp ensure_exit_status(0, _result), do: :ok
  defp ensure_exit_status(_exit_code, result), do: {:error, result}

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
