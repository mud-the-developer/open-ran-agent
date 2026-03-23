defmodule RanFapiCore.DispatcherTest do
  use ExUnit.Case, async: false

  alias RanFapiCore.{Capability, GatewaySession, Health, IR}
  alias RanSchedulerHost.SlotPlan

  test "build_ir turns slot plan into canonical IR" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 10, slot: 7},
      ue_allocations: [%{ue_ref: "ue-1"}],
      fapi_messages: [%{kind: :dl_tti_request, payload: %{mcs: 10}}],
      metadata: %{ue_ref: "ue-1", trace_id: "trace-1"},
      status: :planned
    }

    ir = RanFapiCore.build_ir("cg-001", :stub_fapi_profile, slot_plan)

    assert %IR{
             cell_group_id: "cg-001",
             frame: 10,
             slot: 7,
             profile: :stub_fapi_profile,
             ue_ref: "ue-1"
           } = ir

    assert ir.messages == [%{kind: :dl_tti_request, payload: %{mcs: 10}}]
    assert ir.metadata.scheduler == :cpu_scheduler
  end

  test "dispatch_slot submits the plan through the stub backend" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 1, slot: 2},
      ue_allocations: [],
      fapi_messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{ue_ref: "ue-0001"},
      status: :planned
    }

    assert {:ok, result} =
             RanFapiCore.dispatch_slot("cg-001", :stub_fapi_profile, slot_plan)

    assert result.status == :submitted
    assert result.backend == :stub_fapi_profile
    assert %Health{state: :healthy} = result.health
    assert %IR{frame: 1, slot: 2, ue_ref: "ue-0001"} = result.ir
    assert %Capability{profile: :stub_fapi_profile} = result.backend_capabilities
  end

  test "capabilities resolve through the selected profile" do
    assert {:ok, capabilities} = RanFapiCore.capabilities(:stub_fapi_profile)
    assert %Capability{status: :bootstrap, profile: :stub_fapi_profile} = capabilities

    assert {:ok, local_capabilities} = RanFapiCore.capabilities(:local_fapi_profile)
    assert %Capability{status: :bootstrap, profile: :local_fapi_profile} = local_capabilities

    assert {:ok, aerial_capabilities} = RanFapiCore.capabilities(:aerial_fapi_profile)
    assert %Capability{status: :bootstrap, profile: :aerial_fapi_profile} = aerial_capabilities
  end

  test "invalid IR is rejected before backend submission" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 1, slot: 2},
      ue_allocations: [],
      fapi_messages: [%{kind: :unknown_request, payload: %{}}],
      metadata: %{ue_ref: "ue-0001"},
      status: :planned
    }

    assert {:error, {:invalid_ir, [{:unsupported_message_kind, :unknown_request}]}} =
             RanFapiCore.dispatch_slot("cg-001", :stub_fapi_profile, slot_plan)
  end

  test "gateway session tracks health and supports restart workflow" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 3, slot: 4},
      ue_allocations: [],
      fapi_messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{ue_ref: "ue-session-1"},
      status: :planned
    }

    {:ok, session} = RanFapiCore.start_gateway_session("cg-001", :stub_fapi_profile)
    ir = RanFapiCore.build_ir("cg-001", :stub_fapi_profile, slot_plan)

    assert {:ok, %Capability{profile: :stub_fapi_profile}} = GatewaySession.capability(session)
    assert {:ok, %Health{state: :healthy}} = GatewaySession.health(session)
    assert {:ok, %{health: %Health{state: :healthy}}} = GatewaySession.submit_slot(session, ir)
    assert :ok = GatewaySession.quiesce(session, reason: "drain for switch")
    assert {:ok, %Health{state: :draining}} = GatewaySession.health(session)
    assert :ok = GatewaySession.resume(session)
    assert {:ok, %Health{state: :healthy, restart_count: 1}} = GatewaySession.restart(session)
  end

  test "dispatch_slot can exercise the synthetic port sidecar" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 7, slot: 8},
      ue_allocations: [],
      fapi_messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{ue_ref: "ue-port-1"},
      status: :planned
    }

    assert {:ok, result} =
             RanFapiCore.dispatch_slot("cg-port-001", :stub_fapi_profile, slot_plan,
               transport: :port
             )

    assert %Health{state: :healthy} = result.health
    assert result.health.checks["submitted_slots"] == 1
    assert %Capability{profile: :stub_fapi_profile} = result.backend_capabilities
  end

  test "local and aerial backends use the shared port-backed contract adapter" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 15, slot: 3},
      ue_allocations: [],
      fapi_messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{ue_ref: "ue-native-contract-1"},
      status: :planned
    }

    assert {:ok, local_result} =
             RanFapiCore.dispatch_slot("cg-local-001", :local_fapi_profile, slot_plan)

    assert local_result.health.checks["backend_family"] == "local_du_low"
    assert local_result.health.checks["transport_mode"] == "port"
    assert local_result.health.checks["worker_kind"] == "local_du_low_contract_gateway"
    assert local_result.health.checks["fronthaul_session"] == "local_du_low_port"
    assert local_result.health.checks["transport_worker"] == "local_ring_v1"
    assert local_result.health.checks["submitted_slots"] == 1

    assert %Capability{profile: :local_fapi_profile, status: :bootstrap} =
             local_result.backend_capabilities

    assert {:ok, aerial_result} =
             RanFapiCore.dispatch_slot("cg-aerial-001", :aerial_fapi_profile, slot_plan)

    assert aerial_result.health.checks["backend_family"] == "aerial"
    assert aerial_result.health.checks["transport_mode"] == "port"
    assert aerial_result.health.checks["worker_kind"] == "aerial_contract_gateway"
    assert aerial_result.health.checks["execution_lane"] == "gpu_batch"
    assert aerial_result.health.checks["policy_mode"] == "clean_room"
    assert aerial_result.health.checks["submitted_slots"] == 1

    assert %Capability{profile: :aerial_fapi_profile, status: :bootstrap} =
             aerial_result.backend_capabilities
  end

  test "gateway session with port transport blocks submit while quiesced and resumes cleanly" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 12, slot: 9},
      ue_allocations: [],
      fapi_messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{ue_ref: "ue-port-session-1"},
      status: :planned
    }

    {:ok, session} =
      RanFapiCore.start_gateway_session("cg-port-002", :stub_fapi_profile, transport: :port)

    ir = RanFapiCore.build_ir("cg-port-002", :stub_fapi_profile, slot_plan)

    assert :ok = GatewaySession.quiesce(session, reason: "drain before controlled switch")
    assert :ok = GatewaySession.handle_uplink_indication(session, %{kind: :rx_data_indication})
    assert {:error, :session_quiesced} = GatewaySession.submit_slot(session, ir)

    assert {:ok, %Health{state: :draining, session_status: :quiesced}} =
             GatewaySession.health(session)

    assert :ok = GatewaySession.resume(session)

    assert {:ok, %{health: %Health{state: :healthy, session_status: :active} = health}} =
             GatewaySession.submit_slot(session, ir)

    assert health.checks["submitted_slots"] == 1
    assert health.checks["uplink_indications"] == 1
    assert health.checks["last_uplink_kind"] == "rx_data_indication"
    assert {:ok, %Health{state: :healthy, restart_count: 1}} = GatewaySession.restart(session)
  end

  test "gateway session restart preserves explicit session transport options" do
    slot_plan = %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: 18, slot: 5},
      ue_allocations: [],
      fapi_messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{ue_ref: "ue-local-session-1"},
      status: :planned
    }

    {:ok, session} = RanFapiCore.start_gateway_session("cg-local-opts-001", :local_fapi_profile)
    ir = RanFapiCore.build_ir("cg-local-opts-001", :local_fapi_profile, slot_plan)

    assert {:ok, %{health: %Health{} = health_before}} = GatewaySession.submit_slot(session, ir)
    assert health_before.checks["transport_mode"] == "port"

    assert {:ok, %Health{restart_count: 1}} = GatewaySession.restart(session)

    assert {:ok, %{health: %Health{} = health_after}} = GatewaySession.submit_slot(session, ir)
    assert health_after.checks["transport_mode"] == "port"
    assert health_after.checks["backend_family"] == "local_du_low"
    assert health_after.checks["worker_kind"] == "local_du_low_contract_gateway"
    assert health_after.checks["fronthaul_session"] == "local_du_low_port"
    assert health_after.checks["submitted_slots"] == 1
  end
end
