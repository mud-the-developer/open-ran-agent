defmodule RanCuCp.MixProject do
  use Mix.Project

  def project do
    [
      app: :ran_cu_cp,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {RanCuCp.Application, []}
    ]
  end

  defp deps do
    [
      {:ran_core, in_umbrella: true}
    ]
  end
end
