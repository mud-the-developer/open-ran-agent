defmodule RanFapiCore.NativeGatewayContractTest do
  use ExUnit.Case, async: false

  alias RanFapiCore.{GatewaySession, Health}
  alias RanSchedulerHost.SlotPlan

  test "local_du_low default Port worker exposes adapter-specific health checks" do
    slot_plan = slot_plan("ue-local-native-001", :cpu_scheduler, 21, 3)

    assert {:ok, dispatch_result} =
             RanFapiCore.dispatch_slot("cg-native-local-001", :local_fapi_profile, slot_plan)

    assert dispatch_result.backend == :local_fapi_profile
    assert %Health{state: :healthy, session_status: :active} = dispatch_result.health
    assert dispatch_result.health.checks["backend_family"] == "local_du_low"
    assert dispatch_result.health.checks["worker_kind"] == "local_du_low_contract_gateway"
    assert dispatch_result.health.checks["fronthaul_session"] == "local_du_low_port"
    assert dispatch_result.health.checks["transport_worker"] == "local_ring_v1"
    assert dispatch_result.health.checks["submitted_slots"] == 1

    {:ok, session} =
      RanFapiCore.start_gateway_session("cg-native-local-002", :local_fapi_profile)

    on_exit(fn -> terminate_session(session) end)

    ir = RanFapiCore.build_ir("cg-native-local-002", :local_fapi_profile, slot_plan)

    assert {:ok, %Health{state: :healthy, session_status: :active} = healthy} =
             GatewaySession.health(session)

    assert healthy.checks == %{}

    assert :ok =
             GatewaySession.handle_uplink_indication(session, %{"kind" => "rx_data_indication"})

    assert {:ok, %Health{checks: checks_after_uplink}} = GatewaySession.health(session)
    assert checks_after_uplink["uplink_indications"] == 1
    assert checks_after_uplink["last_uplink_kind"] == "rx_data_indication"
    assert checks_after_uplink["backend_family"] == "local_du_low"
    assert checks_after_uplink["worker_kind"] == "local_du_low_contract_gateway"
    assert checks_after_uplink["fronthaul_session"] == "local_du_low_port"
    assert checks_after_uplink["transport_mode"] == "port"

    assert :ok = GatewaySession.quiesce(session, reason: "maintenance drain")

    assert {:ok, %Health{state: :draining, session_status: :quiesced}} =
             GatewaySession.health(session)

    assert {:error, :session_quiesced} = GatewaySession.submit_slot(session, ir)

    assert :ok = GatewaySession.resume(session)

    assert {:ok, %{health: %Health{state: :healthy, session_status: :active} = resumed}} =
             GatewaySession.submit_slot(session, ir)

    assert resumed.checks["submitted_slots"] == 1
    assert resumed.checks["backend_family"] == "local_du_low"
    assert resumed.checks["worker_kind"] == "local_du_low_contract_gateway"
    assert resumed.checks["fronthaul_session"] == "local_du_low_port"
    assert resumed.checks["transport_mode"] == "port"
  end

  test "aerial default Port worker exposes adapter-specific health checks" do
    slot_plan = slot_plan("ue-aerial-native-001", :cpu_scheduler, 33, 7)

    assert {:ok, dispatch_result} =
             RanFapiCore.dispatch_slot("cg-native-aerial-001", :aerial_fapi_profile, slot_plan)

    assert dispatch_result.backend == :aerial_fapi_profile
    assert %Health{state: :healthy, session_status: :active} = dispatch_result.health
    assert dispatch_result.health.checks["backend_family"] == "aerial"
    assert dispatch_result.health.checks["worker_kind"] == "aerial_contract_gateway"
    assert dispatch_result.health.checks["execution_lane"] == "gpu_batch"
    assert dispatch_result.health.checks["policy_mode"] == "clean_room"
    assert dispatch_result.health.checks["submitted_slots"] == 1

    {:ok, session} =
      RanFapiCore.start_gateway_session("cg-native-aerial-002", :aerial_fapi_profile)

    on_exit(fn -> terminate_session(session) end)

    ir = RanFapiCore.build_ir("cg-native-aerial-002", :aerial_fapi_profile, slot_plan)

    assert {:ok, %Health{state: :healthy, session_status: :active} = healthy} =
             GatewaySession.health(session)

    assert healthy.checks == %{}

    assert :ok = GatewaySession.handle_uplink_indication(session, %{kind: :rx_data_indication})
    assert {:ok, %Health{checks: checks_after_uplink}} = GatewaySession.health(session)
    assert checks_after_uplink["uplink_indications"] == 1
    assert checks_after_uplink["last_uplink_kind"] == "rx_data_indication"
    assert checks_after_uplink["backend_family"] == "aerial"
    assert checks_after_uplink["worker_kind"] == "aerial_contract_gateway"
    assert checks_after_uplink["execution_lane"] == "gpu_batch"
    assert checks_after_uplink["policy_mode"] == "clean_room"
    assert checks_after_uplink["transport_mode"] == "port"

    assert :ok = GatewaySession.quiesce(session, reason: "policy drain")

    assert {:ok, %Health{state: :draining, session_status: :quiesced}} =
             GatewaySession.health(session)

    assert {:error, :session_quiesced} = GatewaySession.submit_slot(session, ir)

    assert :ok = GatewaySession.resume(session)

    assert {:ok, %{health: %Health{state: :healthy, session_status: :active} = resumed}} =
             GatewaySession.submit_slot(session, ir)

    assert resumed.checks["submitted_slots"] == 1
    assert resumed.checks["backend_family"] == "aerial"
    assert resumed.checks["worker_kind"] == "aerial_contract_gateway"
    assert resumed.checks["execution_lane"] == "gpu_batch"
    assert resumed.checks["policy_mode"] == "clean_room"
    assert resumed.checks["transport_mode"] == "port"
  end

  test "strict host probe prevents managed session activation on missing host resources" do
    assert {:error, :host_probe_failed} =
             RanFapiCore.start_gateway_session(
               "cg-native-local-strict-001",
               :local_fapi_profile,
               session_payload: %{
                 fronthaul_session: "fh-strict-contract-001",
                 strict_host_probe: true,
                 host_interface: "definitely-missing-iface"
               }
             )

    assert {:error, :host_probe_failed} =
             RanFapiCore.start_gateway_session(
               "cg-native-aerial-strict-001",
               :aerial_fapi_profile,
               session_payload: %{
                 execution_lane: "gpu-strict-contract-001",
                 vendor_surface: "opaque-lab",
                 strict_host_probe: true,
                 cuda_visible_devices: ""
               }
             )
  end

  defp slot_plan(ue_ref, scheduler, frame, slot) do
    %SlotPlan{
      scheduler: scheduler,
      slot_ref: %{frame: frame, slot: slot},
      ue_allocations: [],
      fapi_messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{ue_ref: ue_ref, trace_id: "trace-#{frame}-#{slot}"},
      status: :planned
    }
  end

  defp terminate_session(pid) when is_pid(pid) do
    Process.exit(pid, :shutdown)
  end
end
