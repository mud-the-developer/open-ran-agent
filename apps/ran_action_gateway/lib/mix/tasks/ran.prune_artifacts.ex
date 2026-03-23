defmodule Mix.Tasks.Ran.PruneArtifacts do
  use Mix.Task

  @shortdoc "Plans or applies bootstrap artifact retention pruning"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    opts = parse_opts(args)

    result =
      if opts[:apply] do
        RanActionGateway.ArtifactRetention.apply(opts)
      else
        {:ok, RanActionGateway.ArtifactRetention.plan(opts)}
      end

    case result do
      {:ok, payload} ->
        Mix.shell().info(JSON.encode!(payload))

      {:error, payload} ->
        Mix.raise(JSON.encode!(payload))
    end
  end

  defp parse_opts(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          apply: :boolean,
          artifact_root: :string,
          json_keep: :integer,
          runtime_keep: :integer,
          release_keep: :integer
        ]
      )

    opts
  end
end
