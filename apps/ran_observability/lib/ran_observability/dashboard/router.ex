defmodule RanObservability.Dashboard.Router do
  @moduledoc false

  alias RanObservability.Dashboard.ActionRunner
  alias RanObservability.Dashboard.DeployRunner

  @spec response_for(String.t(), String.t(), binary()) ::
          {non_neg_integer(), String.t(), binary()}
  def response_for("GET", "/", _body) do
    {:ok, body} = File.read(dashboard_file("index.html"))
    {200, "text/html; charset=utf-8", body}
  end

  def response_for("GET", "/assets/dashboard.css", _body) do
    {:ok, body} = File.read(dashboard_file("assets/dashboard.css"))
    {200, "text/css; charset=utf-8", body}
  end

  def response_for("GET", "/assets/dashboard.js", _body) do
    {:ok, body} = File.read(dashboard_file("assets/dashboard.js"))
    {200, "application/javascript; charset=utf-8", body}
  end

  def response_for("GET", "/api/dashboard", _body) do
    body =
      RanObservability.Dashboard.Snapshot.build()
      |> JSON.encode!()

    {200, "application/json; charset=utf-8", body}
  end

  def response_for("GET", "/api/health", _body) do
    body =
      %{
        status: "ok",
        dashboard: "ran_observability",
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }
      |> JSON.encode!()

    {200, "application/json; charset=utf-8", body}
  end

  def response_for("GET", "/api/deploy/defaults", _body) do
    body =
      DeployRunner.defaults_payload()
      |> JSON.encode!()

    {200, "application/json; charset=utf-8", body}
  end

  def response_for("POST", "/api/actions/run", body) do
    with {:ok, payload} <- JSON.decode(body),
         {:ok, result} <- ActionRunner.run(payload) do
      {200, "application/json; charset=utf-8", JSON.encode!(result)}
    else
      {:error, payload} ->
        {422, "application/json; charset=utf-8", JSON.encode!(payload)}
    end
  end

  def response_for("POST", "/api/deploy/run", body) do
    with {:ok, payload} <- JSON.decode(body),
         {:ok, result} <- DeployRunner.run(payload) do
      {200, "application/json; charset=utf-8", JSON.encode!(result)}
    else
      {:error, payload} ->
        {422, "application/json; charset=utf-8", JSON.encode!(payload)}
    end
  end

  def response_for(method, path, _body) when method in ["GET", "POST"] do
    {404, "text/plain; charset=utf-8", "not found: #{path}"}
  end

  def response_for(_method, _path, _body),
    do: {405, "text/plain; charset=utf-8", "method not allowed"}

  defp dashboard_file(path) do
    Application.app_dir(:ran_observability, Path.join("priv/dashboard", path))
  end
end
