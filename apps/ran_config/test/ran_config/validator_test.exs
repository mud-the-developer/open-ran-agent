defmodule RanConfig.ValidatorTest do
  use ExUnit.Case, async: true

  test "validates a supported single-cell bootstrap config" do
    report =
      RanConfig.validation_report(
        profile: :lab_single_cell_stub,
        default_backend: :stub_fapi_profile,
        scheduler_adapter: :cpu_scheduler,
        cell_groups: [
          %{
            id: "cg-001",
            du: "du-lab-001",
            backend: :stub_fapi_profile,
            failover_targets: [:local_fapi_profile],
            scheduler: :cpu_scheduler
          }
        ]
      )

    assert report.status == :ok
    assert report.cell_group_count == 1
    assert report.errors == []
  end

  test "rejects unsupported scheduler and duplicate cell groups" do
    report =
      RanConfig.validation_report(
        profile: :broken,
        default_backend: :stub_fapi_profile,
        scheduler_adapter: :cpu_scheduler,
        cell_groups: [
          %{id: "cg-001", du: "du-a", backend: :stub_fapi_profile, scheduler: :bad_scheduler},
          %{id: "cg-001", du: "du-b", backend: :stub_fapi_profile, scheduler: :cpu_scheduler}
        ]
      )

    assert report.status == :error
    assert %{field: "cell_groups", message: "ids must be unique"} in report.errors
    assert %{field: "cell_group", message: "cg-001 scheduler must be supported"} in report.errors
  end
end
