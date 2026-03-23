defmodule RanDuHighTest do
  use ExUnit.Case, async: true

  alias RanFapiCore.IR
  alias RanSchedulerHost.SlotPlan

  test "run_slot plans and dispatches through the stub backend" do
    cell_group = RanDuHigh.new_cell_group("cg-001")

    assert {:ok, result} =
             RanDuHigh.run_slot(cell_group, %{
               frame: 42,
               slot: 9,
               ue_ref: "ue-0001",
               metadata: %{trace_id: "trace-42"}
             })

    assert result.status == :submitted
    assert %SlotPlan{scheduler: :cpu_scheduler, status: :planned} = result.slot_plan
    assert %IR{cell_group_id: "cg-001", frame: 42, slot: 9, ue_ref: "ue-0001"} = result.ir
  end

  test "cumac scheduler produces an executable slot plan before southbound dispatch" do
    cell_group = RanDuHigh.new_cell_group("cg-001", scheduler: :cumac_scheduler)

    assert {:ok, result} =
             RanDuHigh.run_slot(cell_group, %{
               frame: 0,
               slot: 0,
               ue_ref: "ue-cumac-001",
               metadata: %{trace_id: "trace-cumac-001"}
             })

    assert %SlotPlan{scheduler: :cumac_scheduler, status: :planned} = result.slot_plan
    assert result.slot_plan.metadata.scheduler_mode == :cumac_contract_host
    assert result.slot_plan.metadata.replay_token == "cumac-0-0"
    assert %IR{cell_group_id: "cg-001", profile: :stub_fapi_profile} = result.ir
  end
end
