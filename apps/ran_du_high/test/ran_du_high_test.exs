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
    capabilities = RanSchedulerHost.CumacScheduler.capabilities()

    assert {:ok, result} =
             RanDuHigh.run_slot(cell_group, %{
               frame: 0,
               slot: 0,
               ue_ref: "ue-cumac-001",
               metadata: %{trace_id: "trace-cumac-001"}
             })

    assert capabilities.support_posture == :bounded_clean_room_runtime
    assert capabilities.promotion_state == :bounded_clean_room_runtime
    assert capabilities.declared_target_profile == "cumac_scheduler_clean_room_runtime_v1"
    assert capabilities.rollback_target == :cpu_scheduler
    assert capabilities.failure_domain == :cell_group

    assert capabilities.supported_claims == [
             :executable_slot_plan_runtime,
             :cell_group_scoped_scheduler_ownership,
             :explicit_cpu_rollback_target
           ]

    assert capabilities.unsupported_claims == [
             :external_scheduler_worker_proof,
             :runtime_timing_guarantee,
             :attach_validation_claim
           ]

    assert capabilities.verify_evidence_refs == [
             "apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs",
             "apps/ran_du_high/test/ran_du_high_test.exs"
           ]

    assert capabilities.rollback_evidence_refs == [
             "apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs",
             "apps/ran_du_high/test/ran_du_high_test.exs"
           ]

    assert capabilities.health_model_ref == "docs/architecture/03-failure-domains.md"

    assert capabilities.failure_domain_refs == [
             "docs/architecture/02-otp-apps-and-supervision.md",
             "docs/architecture/03-failure-domains.md"
           ]

    assert capabilities.future_expansion_requirements == [
             :external_scheduler_worker_contract,
             :runtime_timing_guarantee,
             :attach_validation_evidence
           ]

    assert %SlotPlan{scheduler: :cumac_scheduler, status: :planned} = result.slot_plan
    assert result.slot_plan.metadata.scheduler_mode == :cumac_contract_host
    assert result.slot_plan.metadata.replay_token == "cumac-0-0"

    assert result.slot_plan.metadata.declared_target_profile ==
             "cumac_scheduler_clean_room_runtime_v1"

    assert result.slot_plan.metadata.rollback_target == :cpu_scheduler
    assert result.slot_plan.metadata.failure_domain == :cell_group
    assert result.slot_plan.metadata.support_posture == :bounded_clean_room_runtime
    assert %IR{cell_group_id: "cg-001", profile: :stub_fapi_profile} = result.ir
  end
end
