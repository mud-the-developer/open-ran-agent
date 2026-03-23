defmodule RanObservability.Dashboard do
  @moduledoc """
  Thin launcher for the Symphony-style observability dashboard.
  """

  @spec serve(keyword()) :: {:ok, pid()} | {:error, term()}
  def serve(opts \\ []) do
    with :ok <- ensure_runtime_apps(),
         host <- resolved_host(opts),
         port <- resolved_port(opts),
         {:ok, _pid} = ok <-
           RanObservability.Dashboard.Server.start_link(host: host_to_ip(host), port: port) do
      IO.puts("RAN dashboard listening on http://#{host}:#{port}")
      ok
    else
      {:error, reason} = error ->
        IO.warn("failed to start dashboard: #{inspect(reason)}")
        error
    end
  end

  defp ensure_runtime_apps do
    case Application.ensure_all_started(:ran_observability) do
      {:ok, _started} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolved_host(opts) do
    Keyword.get(
      opts,
      :host,
      System.get_env("RAN_DASHBOARD_HOST") ||
        Application.get_env(:ran_observability, :dashboard_host, "127.0.0.1")
    )
  end

  defp resolved_port(opts) do
    Keyword.get(
      opts,
      :port,
      parse_port(
        System.get_env("RAN_DASHBOARD_PORT") ||
          Application.get_env(:ran_observability, :dashboard_port, 4050)
      )
    )
  end

  defp host_to_ip({_, _, _, _} = ip), do: ip

  defp host_to_ip(host) when is_binary(host) do
    host
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end

  defp parse_port(port) when is_integer(port), do: port
  defp parse_port(port) when is_binary(port), do: String.to_integer(port)
end
