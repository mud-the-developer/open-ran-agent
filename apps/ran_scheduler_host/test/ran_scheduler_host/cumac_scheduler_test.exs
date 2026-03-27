defmodule RanSchedulerHost.CumacSchedulerTest do
  use ExUnit.Case, async: true

  alias RanSchedulerHost.CumacScheduler

  test "capabilities expose bounded clean-room runtime proof metadata" do
    capabilities = CumacScheduler.capabilities()

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

    assert capabilities.verify_evidence_refs == [
             "apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs",
             "apps/ran_du_high/test/ran_du_high_test.exs"
           ]

    assert capabilities.rollback_evidence_refs == [
             "apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs",
             "apps/ran_du_high/test/ran_du_high_test.exs"
           ]
  end

  test "init_session and slot plans keep rollback and ownership bounds explicit" do
    assert {:ok, session} =
             CumacScheduler.init_session(
               pipeline_ref: "cumac-proof-001",
               rollback_target: :cpu_scheduler
             )

    assert session.pipeline_ref == "cumac-proof-001"
    assert session.declared_target_profile == "cumac_scheduler_clean_room_runtime_v1"
    assert session.rollback_target == :cpu_scheduler
    assert session.failure_domain == :cell_group
    assert session.support_posture == :bounded_clean_room_runtime

    slot_plan =
      CumacScheduler.plan_slot(
        %{frame: 4, slot: 2, ue_ref: "ue-cumac-proof-001", metadata: %{trace_id: "trace-4-2"}},
        pipeline_ref: "cumac-proof-001",
        rollback_target: :cpu_scheduler
      )

    assert slot_plan.metadata.pipeline_ref == "cumac-proof-001"
    assert slot_plan.metadata.replay_token == "cumac-4-2"
    assert slot_plan.metadata.declared_target_profile == "cumac_scheduler_clean_room_runtime_v1"
    assert slot_plan.metadata.rollback_target == :cpu_scheduler
    assert slot_plan.metadata.failure_domain == :cell_group
    assert slot_plan.metadata.support_posture == :bounded_clean_room_runtime
  end
end
