defmodule Mix.Tasks.Ran.PackageBootstrap do
  use Mix.Task

  @shortdoc "Builds a bootstrap source bundle with release-time config sanity checks"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")
    Mix.Task.run("app.start")

    with :ok <- load_topology_from_env(),
         {:ok, result} <- RanActionGateway.ReleaseBundle.build(parse_opts(args)) do
      Mix.shell().info(JSON.encode!(result))
    else
      {:error, payload} ->
        Mix.raise(JSON.encode!(payload))
    end
  end

  defp parse_opts(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [bundle_id: :string, output_root: :string, repo_root: :string]
      )

    opts
  end

  defp load_topology_from_env do
    case RanConfig.load_topology_from_env() do
      :ok -> :ok
      {:ok, _report} -> :ok
      {:error, payload} -> {:error, payload}
    end
  end
end
