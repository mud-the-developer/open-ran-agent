defmodule RanFapiCore.NativeGatewayTransportStateTest do
  use ExUnit.Case, async: false

  alias RanFapiCore.{GatewaySession, Health}
  alias RanSchedulerHost.SlotPlan

  test "local_du_low default Port worker exposes transport lifecycle signals" do
    slot_plan = slot_plan("ue-local-transport-001", :cpu_scheduler, 41, 5)
    tmp_dir = probe_fixture_dir("local")
    device_path = Path.join(tmp_dir, "fronthaul.sock")
    File.write!(device_path, "loopback-fh\n")

    {:ok, session} =
      RanFapiCore.start_gateway_session("cg-native-transport-local-001", :local_fapi_profile,
        session_payload: %{
          fronthaul_session: "fh-local-transport-001",
          transport_worker: "ring-local-v3",
          slot_budget_us: 360,
          host_interface: "lo",
          device_path: device_path
        }
      )

    on_exit(fn ->
      terminate_session(session)
      File.rm_rf!(tmp_dir)
    end)

    ir = RanFapiCore.build_ir("cg-native-transport-local-001", :local_fapi_profile, slot_plan)

    assert {:ok, %{health: %Health{state: :healthy, session_status: :active} = health}} =
             GatewaySession.submit_slot(session, ir)

    assert health.restart_count == 0
    assert health.checks["backend_family"] == "local_du_low"
    assert health.checks["worker_kind"] == "local_du_low_contract_gateway"
    assert health.checks["transport_mode"] == "port"
    assert health.checks["fronthaul_session"] == "fh-local-transport-001"
    assert health.checks["transport_worker"] == "ring-local-v3"
    assert health.checks["slot_budget_us"] == 360
    assert health.checks["submitted_slots"] == 1
    assert health.checks["last_batch_size"] == 1
    assert is_integer(health.checks["session_epoch"])
    assert is_binary(health.checks["session_started_at"])
    assert is_binary(health.checks["last_submit_at"])
    assert is_binary(health.checks["last_resume_at"])
    assert health.checks["timing_window_us"] == 360
    assert health.checks["deadline_miss_count"] == 0
    assert health.checks["transport_status"] == "streaming"
    assert health.checks["device_binding"] == "local_du_low://fh-local-transport-001"
    assert health.checks["queue_target"] == "fh-local-transport-001:uplink_ring"
    assert health.checks["last_slot_ref"] == "41:5"
    assert health.checks["submit_window_state"] == "within_budget"

    assert health.checks["device_session_ref"] ==
             "local_du_low://fh-local-transport-001/device_session"

    assert health.checks["device_session_state"] == "active"
    assert is_integer(health.checks["device_generation"])
    assert is_binary(health.checks["last_device_attach_at"])
    assert health.checks["device_profile"] == "fronthaul_loopback"
    assert health.checks["handshake_ref"] == "local_du_low://fh-local-transport-001/handshake"
    assert health.checks["handshake_state"] == "ready"
    assert health.checks["handshake_attempts"] == 1
    assert is_binary(health.checks["last_handshake_at"])
    assert health.checks["activation_gate"] == "warn_only"

    assert health.checks["probe_evidence_ref"] ==
             "probe-evidence://local_du_low/fh-local-transport-001"

    assert is_binary(health.checks["probe_checked_at"])

    assert health.checks["probe_required_resources"] == [
             "netif:lo",
             "path:#{device_path}"
           ]

    assert health.checks["handshake_target"] == "netif:lo -> path:#{device_path}"

    assert health.checks["probe_observations"]["host_interface"]["sysfs_path"] ==
             "/sys/class/net/lo"

    assert health.checks["probe_observations"]["host_interface"]["ready"] == true
    assert health.checks["probe_observations"]["device_path"]["kind"] == "regular"
    assert health.checks["probe_observations"]["device_path"]["open_status"] == "ok"
    assert health.checks["host_probe_ref"] == "probe://local_du_low/fh-local-transport-001"
    assert health.checks["host_probe_status"] == "ready"
    assert health.checks["host_probe_mode"] == "host_checks"
    assert health.checks["host_interface"] == "lo"
    assert health.checks["host_interface_present"] == true
    assert health.checks["host_interface_ready"] == true
    assert health.checks["device_path"] == device_path
    assert health.checks["device_path_present"] == true
    assert health.checks["device_path_usable"] == true
    assert health.checks["probe_failure_count"] == 0

    initial_epoch = health.checks["session_epoch"]
    initial_device_generation = health.checks["device_generation"]

    assert :ok = GatewaySession.handle_uplink_indication(session, %{kind: :rx_data_indication})

    assert {:ok, %Health{checks: after_uplink_checks}} = GatewaySession.health(session)
    assert after_uplink_checks["backend_family"] == "local_du_low"
    assert after_uplink_checks["transport_mode"] == "port"
    assert after_uplink_checks["uplink_ring_depth"] == 1
    assert after_uplink_checks["last_uplink_kind"] == "rx_data_indication"
    assert is_binary(after_uplink_checks["last_uplink_at"])
    assert after_uplink_checks["slot_budget_us"] == 360
    assert after_uplink_checks["transport_status"] == "uplink_buffered"

    assert :ok = GatewaySession.quiesce(session, reason: "timing drain")

    assert {:ok, %Health{state: :draining, session_status: :quiesced, checks: quiesced_checks}} =
             GatewaySession.health(session)

    assert quiesced_checks["drain_reason"] == "timing drain"
    assert is_binary(quiesced_checks["last_quiesce_at"])
    assert quiesced_checks["transport_status"] == "draining"
    assert quiesced_checks["device_session_state"] == "draining"
    assert quiesced_checks["handshake_state"] == "draining"

    assert {:error, :session_quiesced} = GatewaySession.submit_slot(session, ir)

    assert :ok = GatewaySession.resume(session)

    assert {:ok, %Health{state: :healthy, session_status: :active, checks: resumed_checks}} =
             GatewaySession.health(session)

    assert resumed_checks["drain_reason"] == "none"
    assert is_binary(resumed_checks["last_resume_at"])
    assert resumed_checks["transport_status"] == "active"
    assert resumed_checks["device_session_state"] == "active"
    assert resumed_checks["handshake_state"] == "ready"

    assert {:ok, %Health{restart_count: 1}} = GatewaySession.restart(session)

    assert {:ok, %{health: %Health{restart_count: 1} = restarted_health}} =
             GatewaySession.submit_slot(session, ir)

    assert restarted_health.checks["backend_family"] == "local_du_low"
    assert restarted_health.checks["transport_mode"] == "port"
    assert restarted_health.checks["fronthaul_session"] == "fh-local-transport-001"
    assert restarted_health.checks["transport_worker"] == "ring-local-v3"
    assert restarted_health.checks["slot_budget_us"] == 360
    assert restarted_health.checks["submitted_slots"] == 1
    assert restarted_health.checks["uplink_ring_depth"] == 0
    assert restarted_health.checks["last_uplink_kind"] == nil
    assert restarted_health.checks["session_epoch"] != initial_epoch
    assert restarted_health.checks["transport_status"] == "streaming"
    assert restarted_health.checks["device_generation"] != initial_device_generation
    assert restarted_health.checks["device_session_state"] == "active"
    assert restarted_health.checks["handshake_attempts"] == 1
    assert restarted_health.checks["host_probe_status"] == "ready"
  end

  test "aerial default Port worker exposes transport lifecycle signals" do
    slot_plan = slot_plan("ue-aerial-transport-001", :cpu_scheduler, 53, 8)
    tmp_dir = probe_fixture_dir("aerial")
    vendor_socket_path = Path.join(tmp_dir, "vendor.sock")
    device_manifest_path = Path.join(tmp_dir, "device.manifest")
    File.write!(vendor_socket_path, "clean-room-socket\n")
    File.write!(device_manifest_path, "gpu=sim\n")

    {:ok, session} =
      RanFapiCore.start_gateway_session("cg-native-transport-aerial-001", :aerial_fapi_profile,
        session_payload: %{
          execution_lane: "gpu-lane-timing-001",
          batch_window_us: 640,
          vendor_surface: "opaque-lab",
          vendor_socket_path: vendor_socket_path,
          device_manifest_path: device_manifest_path,
          cuda_visible_devices: "0"
        }
      )

    on_exit(fn ->
      terminate_session(session)
      File.rm_rf!(tmp_dir)
    end)

    ir =
      RanFapiCore.build_ir("cg-native-transport-aerial-001", :aerial_fapi_profile, slot_plan)

    assert {:ok, %{health: %Health{state: :healthy, session_status: :active} = health}} =
             GatewaySession.submit_slot(session, ir)

    assert health.restart_count == 0
    assert health.checks["backend_family"] == "aerial"
    assert health.checks["worker_kind"] == "aerial_contract_gateway"
    assert health.checks["transport_mode"] == "port"
    assert health.checks["execution_lane"] == "gpu-lane-timing-001"
    assert health.checks["batch_window_us"] == 640
    assert health.checks["vendor_surface"] == "opaque-lab"
    assert health.checks["submitted_slots"] == 1
    assert health.checks["last_batch_size"] == 1
    assert health.checks["last_batch_class"] == "control"
    assert is_integer(health.checks["session_epoch"])
    assert is_binary(health.checks["session_started_at"])
    assert is_binary(health.checks["last_submit_at"])
    assert health.checks["timing_window_us"] == 640
    assert health.checks["timing_budget_us"] == 640
    assert health.checks["deadline_miss_count"] == 0
    assert health.checks["execution_status"] == "dispatching"
    assert health.checks["device_surface"] == "opaque-lab://execution"
    assert health.checks["policy_checkpoint"] == "slot_dispatched"
    assert health.checks["deadline_state"] == "within_budget"

    assert health.checks["device_session_ref"] ==
             "aerial://opaque-lab/gpu-lane-timing-001/device_session"

    assert health.checks["device_session_state"] == "active"
    assert is_integer(health.checks["device_generation"])
    assert is_binary(health.checks["last_device_attach_at"])
    assert health.checks["device_profile"] == "clean_room_execution"
    assert health.checks["policy_surface_ref"] == "policy://opaque-lab/gpu-lane-timing-001"
    assert health.checks["handshake_ref"] == "aerial://opaque-lab/gpu-lane-timing-001/handshake"
    assert health.checks["handshake_state"] == "ready"
    assert health.checks["handshake_attempts"] == 1
    assert is_binary(health.checks["last_handshake_at"])
    assert health.checks["activation_gate"] == "warn_only"

    assert health.checks["probe_evidence_ref"] ==
             "probe-evidence://aerial/opaque-lab/gpu-lane-timing-001"

    assert is_binary(health.checks["probe_checked_at"])

    assert health.checks["probe_required_resources"] == [
             "path:#{vendor_socket_path}",
             "path:#{device_manifest_path}",
             "env:CUDA_VISIBLE_DEVICES=0"
           ]

    assert health.checks["handshake_target"] ==
             "surface:opaque-lab lane:gpu-lane-timing-001 -> path:#{vendor_socket_path}"

    assert health.checks["probe_observations"]["vendor_socket"]["kind"] == "regular"
    assert health.checks["probe_observations"]["vendor_socket"]["open_status"] == "ok"
    assert health.checks["probe_observations"]["device_manifest"]["format"] == "kv"
    assert health.checks["probe_observations"]["device_manifest"]["read_status"] == "ok"
    assert health.checks["probe_observations"]["device_manifest"]["entry_keys"] == ["gpu"]
    assert health.checks["probe_observations"]["cuda_visible_devices"]["count"] == 1
    assert health.checks["host_probe_ref"] == "probe://aerial/opaque-lab/gpu-lane-timing-001"
    assert health.checks["host_probe_status"] == "ready"
    assert health.checks["host_probe_mode"] == "host_checks"
    assert health.checks["vendor_socket_path"] == vendor_socket_path
    assert health.checks["vendor_socket_present"] == true
    assert health.checks["vendor_socket_usable"] == true
    assert health.checks["device_manifest_path"] == device_manifest_path
    assert health.checks["device_manifest_present"] == true
    assert health.checks["device_manifest_ready"] == true
    assert health.checks["cuda_visible_devices"] == "0"
    assert health.checks["cuda_visible_devices_present"] == true
    assert health.checks["cuda_visible_devices_ready"] == true
    assert health.checks["probe_failure_count"] == 0

    initial_epoch = health.checks["session_epoch"]
    initial_device_generation = health.checks["device_generation"]

    assert :ok = GatewaySession.handle_uplink_indication(session, %{kind: :rx_data_indication})

    assert {:ok, %Health{checks: after_uplink_checks}} = GatewaySession.health(session)
    assert after_uplink_checks["backend_family"] == "aerial"
    assert after_uplink_checks["transport_mode"] == "port"
    assert after_uplink_checks["uplink_queue_depth"] == 1
    assert after_uplink_checks["last_uplink_kind"] == "rx_data_indication"
    assert is_binary(after_uplink_checks["last_uplink_at"])
    assert after_uplink_checks["batch_window_us"] == 640
    assert after_uplink_checks["execution_status"] == "uplink_buffered"
    assert after_uplink_checks["policy_checkpoint"] == "uplink_buffered"

    assert :ok = GatewaySession.quiesce(session, reason: "timing drain")

    assert {:ok, %Health{state: :draining, session_status: :quiesced, checks: quiesced_checks}} =
             GatewaySession.health(session)

    assert quiesced_checks["drain_reason"] == "timing drain"
    assert quiesced_checks["execution_status"] == "quiesced"
    assert quiesced_checks["policy_checkpoint"] == "drain:timing drain"
    assert quiesced_checks["device_session_state"] == "quiesced"
    assert quiesced_checks["handshake_state"] == "draining"

    assert {:error, :session_quiesced} = GatewaySession.submit_slot(session, ir)

    assert :ok = GatewaySession.resume(session)

    assert {:ok, %Health{state: :healthy, session_status: :active, checks: resumed_checks}} =
             GatewaySession.health(session)

    assert resumed_checks["drain_reason"] == "none"
    assert is_binary(resumed_checks["last_resume_at"])
    assert resumed_checks["execution_status"] == "active"
    assert resumed_checks["policy_checkpoint"] == "resumed"
    assert resumed_checks["device_session_state"] == "active"
    assert resumed_checks["handshake_state"] == "ready"

    assert {:ok, %Health{restart_count: 1}} = GatewaySession.restart(session)

    assert {:ok, %{health: %Health{restart_count: 1} = restarted_health}} =
             GatewaySession.submit_slot(session, ir)

    assert restarted_health.checks["backend_family"] == "aerial"
    assert restarted_health.checks["transport_mode"] == "port"
    assert restarted_health.checks["execution_lane"] == "gpu-lane-timing-001"
    assert restarted_health.checks["batch_window_us"] == 640
    assert restarted_health.checks["vendor_surface"] == "opaque-lab"
    assert restarted_health.checks["submitted_slots"] == 1
    assert restarted_health.checks["uplink_queue_depth"] == 0
    assert restarted_health.checks["last_uplink_kind"] == nil
    assert restarted_health.checks["session_epoch"] != initial_epoch
    assert restarted_health.checks["execution_status"] == "dispatching"
    assert restarted_health.checks["device_generation"] != initial_device_generation
    assert restarted_health.checks["device_session_state"] == "active"
    assert restarted_health.checks["handshake_attempts"] == 1
    assert restarted_health.checks["host_probe_status"] == "ready"
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

  defp probe_fixture_dir(prefix) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-native-probe-#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)
    tmp_dir
  end
end
