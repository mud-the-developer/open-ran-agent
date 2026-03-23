defmodule RanConfig.ReleaseCheckTest do
  use ExUnit.Case, async: true

  test "release readiness passes for controlled failover topology" do
    report =
      RanConfig.release_readiness(
        profile: :release_ready_lab,
        default_backend: :stub_fapi_profile,
        scheduler_adapter: :cpu_scheduler,
        cell_groups: [
          %{
            id: "cg-001",
            du: "du-001",
            backend: :stub_fapi_profile,
            failover_targets: [:local_fapi_profile],
            scheduler: :cpu_scheduler
          }
        ]
      )

    assert report.status == :ok
    assert Enum.any?(report.checks, &(&1["name"] == "controlled_failover_ready"))
  end

  test "release readiness rejects missing failover targets" do
    report =
      RanConfig.release_readiness(
        profile: :release_not_ready,
        default_backend: :stub_fapi_profile,
        scheduler_adapter: :cpu_scheduler,
        cell_groups: [
          %{
            id: "cg-001",
            du: "du-001",
            backend: :stub_fapi_profile,
            failover_targets: [],
            scheduler: :cpu_scheduler
          }
        ]
      )

    assert report.status == :error

    assert %{field: "cell_group", message: "cg-001 must declare at least one failover target"} in report.errors
  end
end
