defmodule RanFapiCore.PortGatewayClientTest do
  use ExUnit.Case, async: false

  alias RanFapiCore.{IR, PortGatewayClient}

  test "port gateway client exposes quiesce and resume session semantics" do
    assert {:ok, session} =
             PortGatewayClient.open(
               cell_group_id: "cg-port-client-001",
               profile: :stub_fapi_profile
             )

    assert :ok = PortGatewayClient.activate_cell(session, cell_group_id: "cg-port-client-001")

    assert {:ok, healthy} = PortGatewayClient.health(session)
    assert healthy.state == :healthy
    assert healthy.session_status == :active
    assert healthy.checks["submitted_slots"] == 0
    assert healthy.checks["uplink_indications"] == 0

    assert :ok =
             PortGatewayClient.handle_uplink_indication(session, %{
               kind: :rx_data_indication,
               payload: %{pdus: [%{rnti: 4601}]}
             })

    assert {:ok, after_uplink} = PortGatewayClient.health(session)
    assert after_uplink.checks["uplink_indications"] == 1
    assert after_uplink.checks["last_uplink_kind"] == "rx_data_indication"

    assert :ok = PortGatewayClient.quiesce(session, reason: "drain before switch")

    assert {:ok, draining} = PortGatewayClient.health(session)
    assert draining.state == :draining
    assert draining.session_status == :quiesced

    assert {:error, {"error", "session_quiesced"}} =
             PortGatewayClient.submit_slot(session, sample_ir("cg-port-client-001"))

    assert :ok = PortGatewayClient.resume(session)

    assert {:ok, resumed} = PortGatewayClient.health(session)
    assert resumed.state == :healthy
    assert resumed.session_status == :active

    assert :ok = PortGatewayClient.submit_slot(session, sample_ir("cg-port-client-001"))

    assert {:ok, after_submit} = PortGatewayClient.health(session)
    assert after_submit.checks["submitted_slots"] == 1

    assert :ok = PortGatewayClient.terminate(session)
  end

  test "open session payload config reaches native adapter-specific handlers" do
    tmp_dir = probe_fixture_dir("port-client")
    local_device_path = Path.join(tmp_dir, "fh.sock")
    aerial_vendor_socket_path = Path.join(tmp_dir, "vendor.sock")
    aerial_device_manifest_path = Path.join(tmp_dir, "device.manifest")
    File.write!(local_device_path, "fh-loopback\n")
    File.write!(aerial_vendor_socket_path, "vendor-socket\n")
    File.write!(aerial_device_manifest_path, "gpu=sim\n")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert {:ok, local_session} =
             PortGatewayClient.open(
               cell_group_id: "cg-local-client-001",
               profile: :local_fapi_profile,
               gateway_path:
                 Path.expand(
                   "../../../../native/local_du_low_adapter/bin/contract_gateway",
                   __DIR__
                 ),
               session_payload: %{
                 fronthaul_session: "fh-test-001",
                 transport_worker: "ring-test-v2",
                 slot_budget_us: 320,
                 host_interface: "lo",
                 device_path: local_device_path
               }
             )

    assert :ok =
             PortGatewayClient.activate_cell(local_session, cell_group_id: "cg-local-client-001")

    assert {:ok, local_health} = PortGatewayClient.health(local_session)
    assert local_health.checks["fronthaul_session"] == "fh-test-001"
    assert local_health.checks["transport_worker"] == "ring-test-v2"
    assert local_health.checks["slot_budget_us"] == 320
    assert local_health.checks["activation_gate"] == "warn_only"

    assert local_health.checks["probe_evidence_ref"] ==
             "probe-evidence://local_du_low/fh-test-001"

    assert is_binary(local_health.checks["probe_checked_at"])

    assert local_health.checks["probe_required_resources"] == [
             "netif:lo",
             "path:#{local_device_path}"
           ]

    assert local_health.checks["handshake_target"] == "netif:lo -> path:#{local_device_path}"

    assert local_health.checks["probe_observations"]["host_interface"]["sysfs_path"] ==
             "/sys/class/net/lo"

    assert local_health.checks["probe_observations"]["host_interface"]["ready"] == true
    assert local_health.checks["probe_observations"]["device_path"]["kind"] == "regular"
    assert local_health.checks["probe_observations"]["device_path"]["open_status"] == "ok"
    assert local_health.checks["probe_observations"]["device_path"]["size"] > 0
    assert local_health.checks["host_probe_status"] == "ready"
    assert local_health.checks["host_interface"] == "lo"
    assert local_health.checks["host_interface_ready"] == true
    assert local_health.checks["device_path"] == local_device_path
    assert local_health.checks["device_path_usable"] == true
    assert :ok = PortGatewayClient.terminate(local_session)

    assert {:ok, aerial_session} =
             PortGatewayClient.open(
               cell_group_id: "cg-aerial-client-001",
               profile: :aerial_fapi_profile,
               gateway_path:
                 Path.expand(
                   "../../../../native/aerial_adapter/bin/contract_gateway",
                   __DIR__
                 ),
               session_payload: %{
                 execution_lane: "gpu-test-lane",
                 batch_window_us: 640,
                 vendor_surface: "opaque-lab",
                 vendor_socket_path: aerial_vendor_socket_path,
                 device_manifest_path: aerial_device_manifest_path,
                 cuda_visible_devices: "0"
               }
             )

    assert :ok =
             PortGatewayClient.activate_cell(aerial_session,
               cell_group_id: "cg-aerial-client-001"
             )

    assert {:ok, aerial_health} = PortGatewayClient.health(aerial_session)
    assert aerial_health.checks["execution_lane"] == "gpu-test-lane"
    assert aerial_health.checks["batch_window_us"] == 640
    assert aerial_health.checks["vendor_surface"] == "opaque-lab"
    assert aerial_health.checks["activation_gate"] == "warn_only"

    assert aerial_health.checks["probe_evidence_ref"] ==
             "probe-evidence://aerial/opaque-lab/gpu-test-lane"

    assert is_binary(aerial_health.checks["probe_checked_at"])

    assert aerial_health.checks["probe_required_resources"] == [
             "path:#{aerial_vendor_socket_path}",
             "path:#{aerial_device_manifest_path}",
             "env:CUDA_VISIBLE_DEVICES=0"
           ]

    assert aerial_health.checks["handshake_target"] ==
             "surface:opaque-lab lane:gpu-test-lane -> path:#{aerial_vendor_socket_path}"

    assert aerial_health.checks["probe_observations"]["vendor_socket"]["kind"] == "regular"
    assert aerial_health.checks["probe_observations"]["vendor_socket"]["open_status"] == "ok"
    assert aerial_health.checks["probe_observations"]["device_manifest"]["format"] == "kv"
    assert aerial_health.checks["probe_observations"]["device_manifest"]["read_status"] == "ok"
    assert aerial_health.checks["probe_observations"]["device_manifest"]["entry_keys"] == ["gpu"]
    assert aerial_health.checks["probe_observations"]["cuda_visible_devices"]["count"] == 1
    assert aerial_health.checks["host_probe_status"] == "ready"
    assert aerial_health.checks["vendor_socket_path"] == aerial_vendor_socket_path
    assert aerial_health.checks["vendor_socket_usable"] == true
    assert aerial_health.checks["device_manifest_path"] == aerial_device_manifest_path
    assert aerial_health.checks["device_manifest_ready"] == true
    assert aerial_health.checks["cuda_visible_devices"] == "0"
    assert aerial_health.checks["cuda_visible_devices_ready"] == true
    assert :ok = PortGatewayClient.terminate(aerial_session)
  end

  test "strict host probe blocks activation when required host resources are missing" do
    assert {:ok, local_session} =
             PortGatewayClient.open(
               cell_group_id: "cg-local-strict-client-001",
               profile: :local_fapi_profile,
               gateway_path:
                 Path.expand(
                   "../../../../native/local_du_low_adapter/bin/contract_gateway",
                   __DIR__
                 ),
               session_payload: %{
                 fronthaul_session: "fh-strict-001",
                 host_interface: "definitely-missing-iface",
                 strict_host_probe: true
               }
             )

    assert {:ok, local_health} = PortGatewayClient.health(local_session)
    assert local_health.session_status == :idle
    assert local_health.checks["host_probe_status"] == "blocked"
    assert local_health.checks["strict_host_probe"] == true
    assert local_health.checks["activation_gate"] == "strict"

    assert local_health.checks["probe_evidence_ref"] ==
             "probe-evidence://local_du_low/fh-strict-001"

    assert is_binary(local_health.checks["probe_checked_at"])
    assert local_health.checks["probe_required_resources"] == ["netif:definitely-missing-iface"]
    assert local_health.checks["handshake_target"] == "netif:definitely-missing-iface -> loopback"

    assert local_health.checks["probe_observations"]["host_interface"]["sysfs_path"] ==
             "/sys/class/net/definitely-missing-iface"

    assert local_health.checks["probe_observations"]["host_interface"]["ready"] == false
    assert local_health.checks["host_probe_failures"] == ["missing_host_interface"]
    assert local_health.checks["handshake_state"] == "blocked"
    assert local_health.checks["host_interface_ready"] == false

    assert {:error, {"error", "host_probe_failed"}} =
             PortGatewayClient.activate_cell(local_session,
               cell_group_id: "cg-local-strict-client-001"
             )

    assert :ok = PortGatewayClient.terminate(local_session)

    assert {:ok, aerial_session} =
             PortGatewayClient.open(
               cell_group_id: "cg-aerial-strict-client-001",
               profile: :aerial_fapi_profile,
               gateway_path:
                 Path.expand(
                   "../../../../native/aerial_adapter/bin/contract_gateway",
                   __DIR__
                 ),
               session_payload: %{
                 execution_lane: "gpu-strict-lane",
                 vendor_surface: "opaque-lab",
                 strict_host_probe: true,
                 cuda_visible_devices: ""
               }
             )

    assert {:ok, aerial_health} = PortGatewayClient.health(aerial_session)
    assert aerial_health.session_status == :idle
    assert aerial_health.checks["host_probe_status"] == "blocked"
    assert aerial_health.checks["strict_host_probe"] == true
    assert aerial_health.checks["activation_gate"] == "strict"

    assert aerial_health.checks["probe_evidence_ref"] ==
             "probe-evidence://aerial/opaque-lab/gpu-strict-lane"

    assert is_binary(aerial_health.checks["probe_checked_at"])
    assert aerial_health.checks["probe_required_resources"] == ["clean_room"]

    assert aerial_health.checks["handshake_target"] ==
             "surface:opaque-lab lane:gpu-strict-lane -> clean_room"

    assert aerial_health.checks["probe_observations"]["cuda_visible_devices"]["count"] == 0
    assert aerial_health.checks["host_probe_failures"] == ["missing_cuda_visible_devices"]
    assert aerial_health.checks["handshake_state"] == "blocked"
    assert aerial_health.checks["cuda_visible_devices_ready"] == false

    assert {:error, {"error", "host_probe_failed"}} =
             PortGatewayClient.activate_cell(aerial_session,
               cell_group_id: "cg-aerial-strict-client-001"
             )

    assert :ok = PortGatewayClient.terminate(aerial_session)
  end

  defp sample_ir(cell_group_id) do
    %IR{
      ir_version: "0.1",
      cell_group_id: cell_group_id,
      ue_ref: "ue-port-client-1",
      frame: 10,
      slot: 4,
      profile: :stub_fapi_profile,
      messages: [%{kind: :tx_data_request, payload: %{pdus: []}}],
      metadata: %{scheduler: :cpu_scheduler}
    }
  end

  defp probe_fixture_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
