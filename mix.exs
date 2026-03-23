defmodule OpenRanAgent.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: [],
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test, contract_ci: :test, runtime_ci: :test]]
  end

  defp aliases do
    [
      bootstrap: ["format"],
      contract_ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --exclude runtime_contract"
      ],
      runtime_ci: [
        "test apps/ran_action_gateway/test/ran_action_gateway/cli_test.exs --only runtime_contract",
        "ran.package_bootstrap --bundle-id ci-smoke"
      ],
      ci: ["contract_ci", "runtime_ci"],
      package_bootstrap: ["ran.package_bootstrap"],
      prune_artifacts: ["ran.prune_artifacts"]
    ]
  end
end
