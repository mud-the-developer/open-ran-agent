defmodule RanDuHigh.MixProject do
  use Mix.Project

  def project do
    [
      app: :ran_du_high,
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
      mod: {RanDuHigh.Application, []}
    ]
  end

  defp deps do
    [
      {:ran_core, in_umbrella: true},
      {:ran_fapi_core, in_umbrella: true},
      {:ran_scheduler_host, in_umbrella: true}
    ]
  end
end
