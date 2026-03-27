defmodule RanActionGateway.MockDockerRunner do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def calls do
    Agent.get(__MODULE__, &Enum.reverse/1)
  end

  def run(command, args, _opts \\ []) do
    Agent.update(__MODULE__, &[{command, args} | &1])

    case {command, args} do
      {"docker", ["--version"]} ->
        {"Docker version 29.3.0, build test\n", 0}

      {"docker", ["info"]} ->
        {"Server Version: 29.3.0\n", 0}

      {"docker", ["image", "inspect", image]}
      when image in [
             "oaisoftwarealliance/oai-gnb:develop",
             "oaisoftwarealliance/oai-nr-cuup:develop",
             "oaisoftwarealliance/oai-nr-ue:develop"
           ] ->
        {"[]", 0}

      {"docker", ["compose", "-p", project_name, "-f", compose_path, "up", "-d"]} ->
        if File.exists?(compose_path) do
          {"started #{project_name}\n", 0}
        else
          {"missing compose file\n", 1}
        end

      {"docker",
       ["compose", "-p", project_name, "-f", compose_path, "down", "-v", "--remove-orphans"]} ->
        if File.exists?(compose_path) do
          {"stopped #{project_name}\n", 0}
        else
          {"missing compose file\n", 1}
        end

      {"docker", ["inspect", container_name]} ->
        payload = [
          %{
            "Name" => container_name,
            "State" => %{
              "Running" => true,
              "Status" => "running",
              "Health" => %{"Status" => "healthy"}
            }
          }
        ]

        {JSON.encode!(payload), 0}

      {"docker", ["logs", "--tail", _tail_lines, container_name]} ->
        log =
          cond do
            String.ends_with?(container_name, "-du") ->
              """
              [NR_MAC] I Frame.Slot 512.0
              [NR_MAC] I Frame.Slot 640.0
              """

            String.ends_with?(container_name, "-cucp") ->
              "sending F1 Setup Response\n"

            String.ends_with?(container_name, "-cuup") ->
              "E1 connection established\n"

            String.ends_with?(container_name, "-nr-ue") ->
              """
              == Starting NR UE soft modem
              [NR_RRC] I rrcReconfigurationComplete Encoded 10 bits (2 bytes)
              [OIP] I Interface oaitun_ue1 successfully configured, ip address 12.1.1.3, mask 255.255.255.0 broadcast address 12.1.1.255
              """

            true ->
              "log output for #{container_name}\n"
          end

        {log, 0}

      {"docker", ["pull", image]} ->
        {"pulled #{image}\n", 0}

      _ ->
        {"unexpected command: #{inspect({command, args})}\n", 1}
    end
  end
end

defmodule RanActionGateway.CLITest do
  use ExUnit.Case, async: false

  alias RanActionGateway.CLI
  alias RanActionGateway.Store

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "ranctl-cli-#{System.unique_integer([:positive, :monotonic])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    RanActionGateway.ControlState.reset()

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  test "help returns usage" do
    assert {:usage, %{usage: usage}} = CLI.run(["help"])
    assert usage =~ "bin/ranctl <command>"
  end

  test "plan requires change identifiers and apply requires approval", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      invalid_payload =
        JSON.encode!(%{
          "scope" => "cell_group",
          "cell_group" => "cg-001",
          "reason" => "missing change id",
          "idempotency_key" => "missing-change-id",
          "verify_window" => %{"duration" => "30s", "checks" => ["gateway_healthy"]}
        })

      assert {:error, %{status: "invalid", command: "plan", errors: errors}} =
               CLI.run(["plan", "--json", invalid_payload])

      assert %{field: "change_id", message: "is required"} in errors

      payload = JSON.encode!(base_payload())

      assert {:ok, %{status: "planned"}} = CLI.run(["plan", "--json", payload])
      assert File.exists?(Store.plan_path("chg-test-001"))

      assert {:error, %{status: "approval_required", command: "apply"}} =
               CLI.run(["apply", "--json", payload])
    end)
  end

  test "replacement-track example scopes pass runner validation", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      examples = [
        {"precheck",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/precheck-target-host-open5gs-n79.json"
         ), "target_host"},
        {"plan",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/plan-gnb-bringup-open5gs-n79.json"
         ), "gnb"},
        {"verify",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/verify-attach-ping-open5gs-n79.json"
         ), "ue_session"},
        {"observe",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/observe-failed-ru-sync-open5gs-n79.json"
         ), "ru_link"},
        {"observe",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/observe-registration-rejected-open5gs-n79.json"
         ), "ue_session"},
        {"observe",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/observe-failed-cutover-open5gs-n79.json"
         ), "replacement_cutover"},
        {"capture-artifacts",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/capture-artifacts-failed-cutover-open5gs-n79.json"
         ), "replacement_cutover"},
        {"rollback",
         Path.join(
           repo_root,
           "subprojects/ran_replacement/examples/ranctl/rollback-gnb-cutover-open5gs-n79.json"
         ), "replacement_cutover"}
      ]

      Enum.each(examples, fn {command, path, expected_scope} ->
        result =
          File.cd!(tmp_dir, fn ->
            File.mkdir_p!("artifacts")
            payload = path |> File.read!() |> JSON.decode!() |> JSON.encode!()
            CLI.run([command, "--json", payload])
          end)

        refute match?({:error, %{status: "invalid", errors: [%{field: "scope"} | _]}}, result),
               "expected scope #{expected_scope} from #{path} to pass validation, got: #{inspect(result)}"
      end)
    end)
  end

  test "replacement precheck and verify surface deterministic ngap/core-link artifact fields",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      precheck_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/precheck-target-host-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, precheck} = CLI.run(["precheck", "--json", precheck_payload])
      assert precheck.core_profile == "open5gs_nsa_lab_v1"
      assert precheck.status == "blocked"
      assert precheck.gate_class == "blocked"
      assert precheck.target_ref == "host-n79-lab-01"
      assert precheck.target_profile == "n79_single_ru_single_ue_lab_v1"
      assert precheck.target_backend == "replacement_shadow"
      assert (precheck[:rollback_target] || precheck["rollback_target"]) == "oai_reference"
      assert precheck.rollback_available == true
      assert precheck.conformance_claim.profile == "oai_visible_5g_standards_baseline_v1"
      assert precheck.core_endpoint.profile == "open5gs_nsa_lab_v1"
      assert precheck.core_endpoint.n2["amf_host"] == "10.41.83.45"
      assert get_in(precheck, [:ru_status, :evidence_ref]) =~ "/ru-sync.json"
      assert Enum.any?(precheck.artifacts, &String.ends_with?(&1, "/host-n79-lab-01.json"))
      assert Enum.all?(precheck.artifacts, &File.exists?/1)
      assert File.exists?(Store.precheck_path("chg-ran-repl-precheck-001"))

      assert get_in(precheck, [:core_link_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(precheck, [:interface_status, "ngap", :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(precheck, [:plane_status, :s_plane, :status]) == "blocked"
      assert get_in(precheck, [:plane_status, :m_plane, :status]) == "ok"
      assert get_in(precheck, [:ru_status, :status]) == "blocked"

      assert Map.new(precheck.checks, &{&1["name"], &1["status"]}) == %{
               "core_link_reachable" => "ok",
               "host_preflight" => "blocked",
               "ru_sync" => "blocked"
             }

      verify_request =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/verify-attach-ping-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()

      verify_payload = JSON.encode!(verify_request)
      assert {:ok, plan} = CLI.run(["plan", "--json", verify_payload])
      assert (plan[:target_backend] || plan["target_backend"]) == "replacement_shadow"
      assert (plan[:rollback_target] || plan["rollback_target"]) == "oai_reference"
      assert plan.target_profile == "n79_single_ru_single_ue_lab_v1"
      assert plan.conformance_claim.evidence_tier == "milestone_proof"
      assert plan.core_endpoint.n3["dnn"] == "internet"
      assert Enum.all?(plan[:artifacts] || plan["artifacts"], &File.exists?/1)

      assert {:ok, apply} = CLI.run(["apply", "--json", verify_payload])
      assert (apply[:target_backend] || apply["target_backend"]) == "replacement_shadow"
      assert (apply[:rollback_target] || apply["rollback_target"]) == "oai_reference"
      assert apply.target_profile == "n79_single_ru_single_ue_lab_v1"
      assert apply.conformance_claim.evidence_tier == "milestone_proof"
      assert Enum.all?(apply.artifacts, &File.exists?/1)

      assert {:ok, verify} = CLI.run(["verify", "--json", verify_payload])
      assert verify.status == "ok"
      assert verify.core_profile == "open5gs_nsa_lab_v1"
      assert verify.target_ref == "ue-n79-lab-01"
      assert verify.target_profile == "n79_single_ru_single_ue_lab_v1"
      assert verify.target_backend == "replacement_shadow"
      assert verify.rollback_target == "oai_reference"
      assert verify.rollback_available == true
      assert verify.conformance_claim.evidence_tier == "milestone_proof"
      assert verify.core_endpoint.profile == "open5gs_nsa_lab_v1"

      assert verify.ngap_subset["standards_subset_ref"] =~
               "06-ngap-and-registration-standards-subset.md"

      assert verify.gate_class in ["degraded", "pass"]

      assert get_in(verify, [:interface_status, "ngap", :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(verify, [:core_link_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(verify, [:attach_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json"

      assert get_in(verify, [:plane_status, :u_plane, :status]) == "ok"

      assert get_in(verify, [:plane_status, :u_plane, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json"

      assert get_in(verify, [:session_status, :status]) == "established"
      assert get_in(verify, [:session_status, :pdu_type]) == "ipv4"
      assert get_in(verify, [:session_status, :ping_target]) == "8.8.8.8"
      assert get_in(verify, [:session_status, :evidence_ref]) =~ "/session.json"

      assert get_in(verify, [:pdu_session_status, :status]) == "ok"

      assert get_in(verify, [:pdu_session_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/pdu-session.json"

      assert get_in(verify, [:ping_status, :status]) == "ok"

      assert get_in(verify, [:ping_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json"

      assert get_in(verify, [:interface_status, "f1_u", :status]) == "ok"
      assert get_in(verify, [:interface_status, "gtpu", :status]) == "ok"
      assert verify.summary =~ "UE attach, PDU session, and ping are all proven"
      assert Enum.any?(verify.artifacts, &String.contains?(&1, "/replacement/verify/"))
      assert File.exists?(get_in(verify, [:attach_status, :evidence_ref]))
      assert File.exists?(get_in(verify, [:pdu_session_status, :evidence_ref]))
      assert File.exists?(get_in(verify, [:ping_status, :evidence_ref]))

      assert verify.ngap_procedure_trace.last_observed == "UE Context Release"

      assert Enum.map(verify.ngap_procedure_trace.procedures, & &1.name) == [
               "NG Setup",
               "Initial UE Message",
               "Uplink NAS Transport",
               "Downlink NAS Transport",
               "UE Context Release"
             ]

      assert Enum.all?(verify.ngap_procedure_trace.procedures, &(&1.status == "ok"))

      refute Enum.any?(verify.ngap_procedure_trace.procedures, fn procedure ->
               procedure.name in ["Paging", "Handover Preparation", "Path Switch"]
             end)

      assert get_in(verify, [:release_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert Enum.all?(
               [
                 "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json",
                 "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json",
                 "artifacts/replacement/n79_single_ru_single_ue_lab_v1/pdu-session.json",
                 "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json"
               ],
               &(&1 in verify.artifacts)
             )

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", verify_payload])
      assert capture.status == "ok"
      assert capture.gate_class == "pass"
      assert capture.summary =~ "verified live-lab evidence bundle"
      assert get_in(capture, [:rollback_status, :status]) == "ok"
      assert get_in(capture, [:bundle, :review, :compare_report]) =~ "-compare-report.json"
      assert File.exists?(get_in(capture, [:bundle, :review, :compare_report]))
      assert File.exists?(get_in(capture, [:bundle, :review, :request_snapshot]))
      assert File.exists?(get_in(capture, [:bundle, :review, :rollback_evidence]))
      assert File.exists?(get_in(capture, [:attach_status, :evidence_ref]))
      assert File.exists?(get_in(capture, [:pdu_session_status, :evidence_ref]))
      assert File.exists?(get_in(capture, [:ping_status, :evidence_ref]))
    end)
  end

  test "target-host lifecycle preserves declared lane targets and deterministic artifacts",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      load = fn name ->
        Path.join(repo_root, "subprojects/ran_replacement/examples/ranctl/#{name}")
        |> File.read!()
        |> JSON.decode!()
      end

      precheck_request =
        load.("plan-target-host-open5gs-n79.json")
        |> put_in(["metadata", "replacement", "action"], "precheck")
        |> Map.put("dry_run", true)
        |> Map.put("reason", "precheck target-host bring-up on the declared n79 replacement lane")
        |> Map.put("idempotency_key", "ran-repl-target-host-precheck-001")
        |> JSON.encode!()

      assert {:ok, precheck} = CLI.run(["precheck", "--json", precheck_request])
      assert precheck.status == "blocked"
      assert File.exists?(Store.precheck_path("chg-ran-repl-target-host-001"))

      assert {:ok, plan} =
               CLI.run([
                 "plan",
                 "--json",
                 load.("plan-target-host-open5gs-n79.json") |> JSON.encode!()
               ])

      assert plan.target_ref == "host-n79-lab-01"
      assert (plan[:target_backend] || plan["target_backend"]) == "replacement_shadow"
      assert (plan[:rollback_target] || plan["rollback_target"]) == "oai_reference"
      assert File.exists?(Store.plan_path("chg-ran-repl-target-host-001"))

      assert {:ok, apply} =
               CLI.run([
                 "apply",
                 "--json",
                 load.("apply-target-host-open5gs-n79.json") |> JSON.encode!()
               ])

      assert apply.target_ref == "host-n79-lab-01"
      assert (apply[:target_backend] || apply["target_backend"]) == "replacement_shadow"
      assert (apply[:rollback_target] || apply["rollback_target"]) == "oai_reference"
      assert File.exists?(Store.change_state_path("chg-ran-repl-target-host-001"))

      assert {:ok, verify} =
               CLI.run([
                 "verify",
                 "--json",
                 load.("verify-target-host-open5gs-n79.json") |> JSON.encode!()
               ])

      assert verify.target_ref == "host-n79-lab-01"
      assert (verify[:target_backend] || verify["target_backend"]) == "replacement_shadow"
      assert (verify[:rollback_target] || verify["rollback_target"]) == "oai_reference"
      assert File.exists?(Store.verify_path("chg-ran-repl-target-host-001"))

      assert {:ok, capture} =
               CLI.run([
                 "capture-artifacts",
                 "--json",
                 load.("capture-artifacts-target-host-open5gs-n79.json") |> JSON.encode!()
               ])

      assert capture.target_ref == "host-n79-lab-01"
      assert (capture[:rollback_target] || capture["rollback_target"]) == "oai_reference"

      assert get_in(capture, [:bundle, :workflow, :precheck]) ==
               Store.precheck_path("chg-ran-repl-target-host-001")

      assert get_in(capture, [:bundle, :workflow, :plan]) ==
               Store.plan_path("chg-ran-repl-target-host-001")

      assert File.exists?(Store.capture_path("inc-ran-repl-target-host-001"))

      assert {:ok, rollback} =
               CLI.run([
                 "rollback",
                 "--json",
                 load.("rollback-target-host-open5gs-n79.json") |> JSON.encode!()
               ])

      assert rollback.target_ref == "host-n79-lab-01"
      assert (rollback[:target_backend] || rollback["target_backend"]) == "oai_reference"
      assert (rollback[:rollback_target] || rollback["rollback_target"]) == "oai_reference"
      assert (rollback[:restored_from] || rollback["restored_from"]) == "replacement_shadow"
      assert File.exists?(Store.approval_path("chg-ran-repl-target-host-001", "rollback"))
    end)
  end

  test "replacement observe surfaces deterministic ngap/core-link artifact fields",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      observe_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/observe-registration-rejected-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, observe} = CLI.run(["observe", "--json", observe_payload])
      assert observe.core_profile == "open5gs_nsa_lab_v1"
      assert observe.gate_class == "degraded"

      assert get_in(observe, [:interface_status, "ngap", :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(observe, [:core_link_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(observe, [:attach_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json"

      assert observe.ngap_procedure_trace.last_observed == "UE Context Release"

      assert Map.new(observe.ngap_procedure_trace.procedures, &{&1.name, &1.status}) == %{
               "NG Setup" => "ok",
               "Initial UE Message" => "ok",
               "Uplink NAS Transport" => "ok",
               "Downlink NAS Transport" => "failed",
               "UE Context Release" => "ok"
             }

      refute Enum.any?(observe.ngap_procedure_trace.procedures, fn procedure ->
               procedure.name in ["Paging", "Handover Preparation", "Path Switch"]
             end)

      assert get_in(observe, [:release_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"
    end)
  end

  test "replacement capture-artifacts surfaces deterministic ngap procedure evidence",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      capture_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/capture-artifacts-registration-rejected-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", capture_payload])
      assert capture.gate_class == "blocked"
      assert capture.failure_class == "core_failure"
      assert capture.rollback_target == "oai_reference"
      assert capture.rollback_available == true
      assert capture.ngap_procedure_trace.last_observed == "UE Context Release"

      assert get_in(capture, [:release_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert Map.new(capture.ngap_procedure_trace.procedures, &{&1.name, &1.status}) == %{
               "NG Setup" => "ok",
               "Initial UE Message" => "ok",
               "Uplink NAS Transport" => "ok",
               "Downlink NAS Transport" => "failed",
               "UE Context Release" => "ok"
             }

      refute Enum.any?(capture.ngap_procedure_trace.procedures, fn procedure ->
               procedure.name in ["Paging", "Handover Preparation", "Path Switch"]
             end)

      assert Enum.any?(capture.checks, fn check ->
               check["name"] == "UE Context Release" and check["status"] == "ok"
             end)

      assert get_in(capture, [:bundle, :declared_lane_evidence, :attach_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json"

      assert get_in(capture, [:bundle, :declared_lane_evidence, :registration_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"
    end)
  end

  test "replacement RU observe and capture preserve replayable failure-class evidence",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      observe_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/observe-failed-ru-sync-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, observe} = CLI.run(["observe", "--json", observe_payload])
      assert observe.gate_class == "degraded"
      assert observe.failure_class == "ru_failure"
      assert observe.summary =~ "RU sync is degraded"
      assert get_in(observe, [:ru_status, :status]) == "blocked"
      assert get_in(observe, [:plane_status, :s_plane, :status]) == "degraded"
      assert get_in(observe, [:plane_status, :u_plane, :status]) == "blocked"
      assert get_in(observe, [:interface_status, "ru_fronthaul", :status]) == "blocked"

      capture_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/capture-artifacts-failed-ru-sync-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", capture_payload])
      assert capture.gate_class == "degraded"
      assert capture.failure_class == "ru_failure"
      assert capture.summary =~ "RU failure evidence bundle"
      assert get_in(capture, [:ru_status, :status]) == "blocked"
      assert get_in(capture, [:rollback_status, :status]) == "pending"

      assert Enum.any?(capture.checks, fn check ->
               check["name"] == "host_preflight_reviewed" and check["status"] == "ok"
             end)

      assert Enum.any?(capture.checks, fn check ->
               check["name"] == "ru_sync_reviewed" and check["status"] == "ok"
             end)

      compare_report =
        get_in(capture, [:bundle, :review, :compare_report])
        |> File.read!()
        |> JSON.decode!()

      assert compare_report["failure_class"] == "ru_failure"
      assert compare_report["comparison_scope"] == "ru_sync"

      rollback_evidence =
        get_in(capture, [:bundle, :review, :rollback_evidence])
        |> File.read!()
        |> JSON.decode!()

      assert rollback_evidence["failure_class"] == "ru_failure"

      assert get_in(rollback_evidence, ["ngap_subset", "standards_subset_ref"]) =~
               "06-ngap-and-registration-standards-subset.md"

      assert get_in(rollback_evidence, ["post_rollback_state", "restored_from"]) ==
               "replacement_shadow"
    end)
  end

  test "replacement control-plane observe surfaces f1-c/e1ap and rollback evidence",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      observe_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/packages/f1e1_control_edge/examples/observe-failed-cutover.request.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, observe} = CLI.run(["observe", "--json", observe_payload])
      assert observe.core_profile == "open5gs_nsa_lab_v1"
      assert observe.gate_class == "degraded"
      assert observe.failure_class == "cutover_or_rollback_failure"

      assert get_in(observe, [:plane_status, :c_plane, :status]) == "degraded"

      assert get_in(observe, [:plane_status, :c_plane, :reason]) =~
               "partially healthy but not ready for leave-running"

      assert get_in(observe, [:plane_status, :c_plane, :evidence_ref]) =~
               "artifacts/replacement/observe/"

      assert get_in(observe, [:interface_status, "f1_c", :status]) == "degraded"

      assert get_in(observe, [:interface_status, "f1_c", :evidence_ref]) =~
               "artifacts/replacement/observe/"

      assert get_in(observe, [:interface_status, "f1_c", :reason]) =~
               "association or configuration state diverged"

      assert get_in(observe, [:interface_status, "e1ap", :status]) == "degraded"

      assert get_in(observe, [:interface_status, "e1ap", :evidence_ref]) =~
               "artifacts/replacement/observe/"

      assert get_in(observe, [:interface_status, "e1ap", :reason]) =~
               "bearer or activity-state coordination diverged"

      assert get_in(observe, [:rollback_status, :status]) == "pending"

      assert get_in(observe, [:rollback_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/rollback.json"

      assert get_in(observe, [:rollback_status, :reason]) =~
               "rollback is available but not yet executed"
    end)
  end

  test "replacement verify can use virtual replacement state when generic change artifacts are absent",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      verify_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/verify-attach-ping-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, verify} = CLI.run(["verify", "--json", verify_payload])
      assert verify.core_profile == "open5gs_nsa_lab_v1"
      assert verify.gate_class in ["degraded", "pass"]

      assert get_in(verify, [:interface_status, "ngap", :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(verify, [:core_link_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(verify, [:attach_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json"

      assert get_in(verify, [:pdu_session_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/pdu-session.json"

      assert get_in(verify, [:ping_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json"

      assert verify.ngap_procedure_trace.last_observed == "UE Context Release"

      assert Enum.map(verify.ngap_procedure_trace.procedures, & &1.name) == [
               "NG Setup",
               "Initial UE Message",
               "Uplink NAS Transport",
               "Downlink NAS Transport",
               "UE Context Release"
             ]

      assert Enum.all?(verify.ngap_procedure_trace.procedures, &(&1.status == "ok"))
    end)
  end

  test "replacement user-plane observe and capture surface ping failure semantics",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      observe_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/observe-ping-failed-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, observe} = CLI.run(["observe", "--json", observe_payload])
      assert observe.gate_class == "degraded"
      assert observe.failure_class == "user_plane_failure"
      assert observe.summary =~ "ping diverged on the declared route"
      assert get_in(observe, [:plane_status, :u_plane, :status]) == "degraded"
      assert get_in(observe, [:pdu_session_status, :status]) == "ok"

      assert get_in(observe, [:pdu_session_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/pdu-session.json"

      assert get_in(observe, [:ping_status, :status]) == "failed"

      assert get_in(observe, [:ping_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json"

      assert get_in(observe, [:interface_status, "f1_u", :status]) == "degraded"
      assert get_in(observe, [:interface_status, "gtpu", :status]) == "degraded"
      assert get_in(observe, [:rollback_status, :status]) == "pending"
      assert get_in(observe, [:rollback_status, :reason]) =~ "user-plane route remains unresolved"

      capture_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/capture-artifacts-ping-failed-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", capture_payload])
      assert capture.gate_class == "degraded"
      assert capture.failure_class == "user_plane_failure"
      assert capture.summary =~ "user-plane evidence bundle after ping failed"
      assert get_in(capture, [:plane_status, :u_plane, :status]) == "degraded"
      assert get_in(capture, [:pdu_session_status, :status]) == "ok"
      assert get_in(capture, [:ping_status, :status]) == "failed"
      assert get_in(capture, [:interface_status, "f1_u", :status]) == "degraded"
      assert get_in(capture, [:interface_status, "gtpu", :status]) == "degraded"
      assert get_in(capture, [:rollback_status, :status]) == "pending"
    end)
  end

  test "replacement capture-artifacts and rollback surface review semantics for rollback evidence",
       %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      repo_root = Path.expand("../../../..", __DIR__)

      capture_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/capture-artifacts-failed-cutover-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", capture_payload])
      assert capture.gate_class == "blocked"
      assert capture.failure_class == "cutover_or_rollback_failure"
      assert capture.rollback_target == "oai_reference"
      assert capture.rollback_available == true
      assert capture.summary =~ "failed replacement evidence bundle"
      assert capture.target_profile == "n79_single_ru_single_ue_lab_v1"
      assert capture.conformance_claim.evidence_tier == "milestone_proof"
      assert capture.core_endpoint.n2["amf_host"] == "10.41.83.45"

      assert "inspect the compare report before another replacement mutation" in capture.suggested_next

      assert get_in(capture, [:interface_status, "ngap", :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(capture, [:release_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(capture, [:rollback_status, :status]) == "pending"

      assert get_in(capture, [:rollback_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/rollback.json"

      assert get_in(capture, [:ngap_procedure_trace, :last_observed]) == "UE Context Release"

      assert Enum.any?(
               capture.checks,
               &(&1["name"] == "compare_report_ready" and &1["status"] == "ok")
             )

      assert Enum.any?(capture.artifacts, &String.ends_with?(&1, "-compare-report.json"))
      assert Enum.any?(capture.artifacts, &String.ends_with?(&1, "-rollback-evidence.json"))
      assert File.exists?(get_in(capture, [:bundle, :review, :compare_report]))
      assert File.exists?(get_in(capture, [:bundle, :review, :request_snapshot]))
      assert File.exists?(get_in(capture, [:bundle, :review, :rollback_evidence]))
      assert File.exists?(get_in(capture, [:rollback_status, :evidence_ref]))

      rollback_payload =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/rollback-gnb-cutover-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()
        |> JSON.encode!()

      assert {:ok, rollback} = CLI.run(["rollback", "--json", rollback_payload])
      assert rollback.gate_class == "pass"
      assert rollback.failure_class == "cutover_or_rollback_failure"
      assert rollback.rollback_target == "oai_reference"
      assert rollback.rollback_available == true
      assert rollback.approval_required == true
      assert rollback.restored_from == "replacement_primary"
      assert rollback.summary =~ "from replacement_primary to the declared oai_reference target"
      assert rollback.summary =~ "declared oai_reference target"
      assert rollback.target_profile == "n79_single_ru_single_ue_lab_v1"
      assert rollback.conformance_claim.evidence_tier == "milestone_proof"
      assert "review the compare report that triggered rollback" in rollback.suggested_next
      assert get_in(rollback, [:rollback_status, :status]) == "ok"

      assert get_in(rollback, [:rollback_status, :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/rollback.json"

      assert get_in(rollback, [:interface_status, "ngap", :evidence_ref]) ==
               "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

      assert get_in(rollback, [:ngap_procedure_trace, :last_observed]) == "UE Context Release"

      assert Enum.any?(rollback.checks, fn check ->
               check["name"] == "approval_evidence_present" and check["status"] == "ok"
             end)

      assert Enum.any?(rollback.artifacts, &String.ends_with?(&1, "/post-rollback-verify.json"))
      assert File.exists?(Store.change_state_path("chg-ran-repl-rollback-001"))
      assert File.exists?(Store.approval_path("chg-ran-repl-rollback-001", "rollback"))
      assert File.exists?(Store.rollback_plan_path("chg-ran-repl-rollback-001"))
      assert File.exists?(get_in(rollback, [:rollback_status, :evidence_ref]))
      assert File.exists?(get_in(rollback, [:attach_status, :evidence_ref]))

      post_rollback_verify =
        get_in(rollback, [:rollback_status, :evidence_ref])
        |> File.read!()
        |> JSON.decode!()

      assert post_rollback_verify["restored_from"] == "replacement_primary"
      assert post_rollback_verify["rollback_target"] == "oai_reference"

      assert get_in(post_rollback_verify, ["restored_state", "summary"]) =~
               "reviewable without SSH archaeology"

      assert "post_rollback_verify_recorded" in post_rollback_verify["verification_checks"]
    end)
  end

  test "precheck includes config validation and cell-group existence", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      payload = JSON.encode!(base_payload())

      assert {:ok,
              %{status: "ok", command: "precheck", config_report: config_report, checks: checks}} =
               CLI.run(["precheck", "--json", payload])

      assert config_report.status == :ok

      assert Enum.any?(
               checks,
               &(&1["name"] == "config_shape_present" and &1["status"] == "passed")
             )

      assert Enum.any?(checks, &(&1["name"] == "cell_group_exists" and &1["status"] == "passed"))

      assert Enum.any?(
               checks,
               &(&1["name"] == "target_preprovisioned" and &1["status"] == "passed")
             )
    end)
  end

  test "plan rejects backend targets that are not pre-provisioned", %{tmp_dir: tmp_dir} do
    original_cell_groups = Application.get_env(:ran_config, :cell_groups)

    Application.put_env(
      :ran_config,
      :cell_groups,
      [
        %{
          id: "cg-001",
          du: "du-test-001",
          backend: :stub_fapi_profile,
          failover_targets: [:local_fapi_profile],
          scheduler: :cpu_scheduler
        }
      ],
      persistent: true
    )

    on_exit(fn ->
      Application.put_env(:ran_config, :cell_groups, original_cell_groups, persistent: true)
    end)

    File.cd!(tmp_dir, fn ->
      payload = JSON.encode!(base_payload(%{"target_backend" => "aerial_fapi_profile"}))

      assert {:error, %{status: "policy_denied", policy: policy, errors: errors}} =
               CLI.run(["plan", "--json", payload])

      assert policy.allowed_targets == ["stub_fapi_profile", "local_fapi_profile"]
      assert [%{field: "target_backend"} | _] = errors
    end)
  end

  test "approved lifecycle writes plan, state, verify, and rollback artifacts", %{
    tmp_dir: tmp_dir
  } do
    File.cd!(tmp_dir, fn ->
      request = base_payload(%{"approval" => approval_payload()})
      payload = JSON.encode!(request)

      assert {:ok, %{status: "planned", rollback_target: "stub_fapi_profile"} = plan} =
               CLI.run(["plan", "--json", payload])

      assert File.exists?(Store.rollback_plan_path("chg-test-001"))

      assert plan["approval_fields_required"] == [
               "approved",
               "approved_by",
               "approved_at",
               "ticket_ref",
               "source"
             ]

      assert {:ok, %{status: "applied", approval_ref: approval_ref}} =
               CLI.run(["apply", "--json", payload])

      assert File.exists?(approval_ref)
      assert {:ok, %{status: "verified"}} = CLI.run(["verify", "--json", payload])
      assert File.exists?(Store.change_state_path("chg-test-001"))
      assert File.exists?(Store.verify_path("chg-test-001"))

      failure_payload =
        request
        |> Map.put("metadata", %{"simulate_failure" => true})
        |> JSON.encode!()

      assert {:ok, %{status: "failed", next: ["capture-artifacts", "rollback"]}} =
               CLI.run(["verify", "--json", failure_payload])

      assert {:ok, %{status: "rolled_back", target_backend: "stub_fapi_profile"}} =
               CLI.run(["rollback", "--json", payload])

      assert File.exists?(Store.approval_path("chg-test-001", "rollback"))
    end)
  end

  test "runtime-enabled commands fail clearly when runtime_contract metadata is missing", %{
    tmp_dir: tmp_dir
  } do
    runtime_fixture = build_runtime_fixture(tmp_dir)

    payload =
      base_payload(%{
        "approval" => approval_payload(),
        "metadata" => %{
          "oai_runtime" => oai_runtime_payload(runtime_fixture)
        }
      })
      |> JSON.encode!()

    File.cd!(tmp_dir, fn ->
      assert {:error, %{status: "invalid", command: "precheck", errors: errors}} =
               CLI.run(["precheck", "--json", payload])

      assert %{field: "runtime_contract", message: message} =
               Enum.find(errors, &(&1.field == "runtime_contract"))

      assert message =~ "metadata.runtime_contract"
    end)
  end

  @tag :runtime_contract
  test "oai runtime path generates compose assets and executes docker lifecycle", %{
    tmp_dir: tmp_dir
  } do
    start_supervised!(RanActionGateway.MockDockerRunner)

    original_runner = Application.get_env(:ran_action_gateway, :command_runner)

    Application.put_env(
      :ran_action_gateway,
      :command_runner,
      RanActionGateway.MockDockerRunner,
      persistent: true
    )

    on_exit(fn ->
      Application.put_env(
        :ran_action_gateway,
        :command_runner,
        original_runner,
        persistent: true
      )
    end)

    runtime_fixture = build_runtime_fixture(tmp_dir)

    payload =
      base_payload(%{
        "approval" => approval_payload(),
        "metadata" => %{
          "oai_runtime" =>
            oai_runtime_payload(runtime_fixture, %{"project_name" => "test-oai-du"}),
          "runtime_contract" => runtime_contract_payload()
        }
      })
      |> JSON.encode!()

    File.cd!(tmp_dir, fn ->
      assert {:ok, %{status: "ok", runtime: runtime}} = CLI.run(["precheck", "--json", payload])
      assert runtime.runtime_mode == "docker_compose_rfsim_f1"
      assert Enum.any?(runtime.checks, &(&1["name"] == "docker_available"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "du_conf_declares_f1_transport"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "du_conf_declares_rfsimulator"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "du_conf_patch_points_present"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "cucp_conf_patch_points_present"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "cuup_conf_patch_points_present"))

      assert {:ok, plan} = CLI.run(["plan", "--json", payload])
      assert plan["runtime_mode"] == "docker_compose_rfsim_f1"
      assert plan["runtime_contract"]["version"] == "ranctl.runtime.v1"
      assert plan["runtime_contract"]["release_unit"] == "bootstrap_source_bundle"
      assert plan["runtime_contract"]["release_ref"] == "source-checkout@cli-test"
      assert plan["runtime_contract"]["entrypoint"] == "bin/ranctl"
      assert plan["runtime_contract"]["runtime_mode"] == "docker_compose_rfsim_f1"
      assert is_binary(plan["runtime_contract"]["runtime_digest"])
      assert File.exists?(plan["runtime_plan"].compose_path)
      assert File.exists?(plan["runtime_plan"].runtime_spec["rendered_du_conf_path"])
      assert File.exists?(plan["runtime_plan"].runtime_spec["rendered_cucp_conf_path"])
      assert File.exists?(plan["runtime_plan"].runtime_spec["rendered_cuup_conf_path"])

      assert File.read!(plan["runtime_plan"].runtime_spec["rendered_du_conf_path"]) =~
               "remote_n_address = \"oai-cucp\""

      assert File.read!(plan["runtime_plan"].runtime_spec["rendered_cucp_conf_path"]) =~
               "local_s_address = \"10.213.72.2\""

      assert File.read!(plan["runtime_plan"].runtime_spec["rendered_cuup_conf_path"]) =~
               "local_s_address = \"10.213.73.2\""

      assert {:ok, apply} = CLI.run(["apply", "--json", payload])
      assert apply["runtime_result"].project_name == "test-oai-du"

      assert apply["runtime_contract"]["runtime_digest"] ==
               plan["runtime_contract"]["runtime_digest"]

      assert {:ok, approval_artifact} = Store.read_json(apply.approval_ref)
      assert approval_artifact["runtime_contract"]["release_ref"] == "source-checkout@cli-test"

      assert {:ok, verify} = CLI.run(["verify", "--json", payload])
      assert verify["runtime_contract"]["runtime_mode"] == "docker_compose_rfsim_f1"

      assert Enum.any?(
               verify.checks,
               &(&1["name"] == "runtime:test-oai-du-du" and &1["status"] == "passed")
             )

      assert Enum.any?(verify.checks, &(&1["name"] == "du_log_f1_setup_complete"))
      assert Enum.any?(verify.checks, &(&1["name"] == "cuup_log_e1_established"))

      assert File.exists?(Store.runtime_log_path("chg-test-001", "test-oai-du-du"))

      assert {:ok, observe} = CLI.run(["observe", "--json", payload])
      assert observe.config.profile == :bootstrap
      assert observe.config.cell_group.id == "cg-001"
      assert observe.config.release_readiness.status == :ok
      assert observe.snapshot.retention.summary.prune_count == 0
      assert observe.runtime.runtime_mode == "docker_compose_rfsim_f1"

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", payload])
      assert capture.bundle.workflow.plan == Store.plan_path("chg-test-001")
      assert capture.bundle.workflow.change_state == Store.change_state_path("chg-test-001")
      assert capture.bundle.workflow.verify == Store.verify_path("chg-test-001")
      assert capture.bundle.workflow.rollback_plan == Store.rollback_plan_path("chg-test-001")
      assert length(capture.bundle.workflow.approvals) == 1
      assert length(capture.bundle.runtime.logs) == 3
      assert length(capture.bundle.runtime.configs) == 3

      assert {:ok, rollback} = CLI.run(["rollback", "--json", payload])
      assert rollback["runtime_result"].project_name == "test-oai-du"
      assert rollback["runtime_contract"]["release_unit"] == "bootstrap_source_bundle"

      assert Enum.any?(RanActionGateway.MockDockerRunner.calls(), fn
               {"docker", ["compose", "-p", "test-oai-du", "-f", _, "up", "-d"]} -> true
               _ -> false
             end)

      assert Enum.any?(RanActionGateway.MockDockerRunner.calls(), fn
               {"docker",
                ["compose", "-p", "test-oai-du", "-f", _, "down", "-v", "--remove-orphans"]} ->
                 true

               _ ->
                 false
             end)
    end)
  end

  @tag :runtime_contract
  test "public OAI RFsim example requests use repo-local proof assets and expose simulation evidence",
       %{tmp_dir: tmp_dir} do
    start_supervised!(RanActionGateway.MockDockerRunner)

    original_runner = Application.get_env(:ran_action_gateway, :command_runner)

    Application.put_env(
      :ran_action_gateway,
      :command_runner,
      RanActionGateway.MockDockerRunner,
      persistent: true
    )

    on_exit(fn ->
      Application.put_env(
        :ran_action_gateway,
        :command_runner,
        original_runner,
        persistent: true
      )
    end)

    repo_root = Path.expand("../../../..", __DIR__)

    load = fn name ->
      Path.join(repo_root, "examples/ranctl/#{name}")
      |> File.read!()
      |> JSON.decode!()
      |> absolutize_public_oai_paths(repo_root)
    end

    File.cd!(tmp_dir, fn ->
      precheck_payload = load.("precheck-oai-du-docker.json") |> JSON.encode!()
      apply_payload = load.("apply-oai-du-docker.json") |> JSON.encode!()
      verify_payload = load.("verify-oai-du-docker.json") |> JSON.encode!()
      rollback_payload = load.("rollback-oai-du-docker.json") |> JSON.encode!()

      assert {:ok, precheck} = CLI.run(["precheck", "--json", precheck_payload])
      assert precheck.status == "ok"
      assert precheck.simulation_lane.claim_scope == "repo_local_simulation"
      assert precheck.simulation_lane.live_lab_claim == false

      assert Enum.any?(
               precheck.checks,
               &(&1["name"] == "simulation_attach_evidence_ready" and &1["status"] == "passed")
             )

      assert {:ok, %{status: "planned"}} = CLI.run(["plan", "--json", apply_payload])
      assert {:ok, %{status: "applied"}} = CLI.run(["apply", "--json", apply_payload])

      assert {:ok, verify} = CLI.run(["verify", "--json", verify_payload])
      assert verify.status == "verified"
      assert verify.simulation_lane.claim_scope == "repo_local_simulation"
      assert get_in(verify, [:attach_status, :status]) == "ok"
      assert get_in(verify, [:registration_status, :status]) == "ok"
      assert get_in(verify, [:session_status, :status]) == "established"
      assert get_in(verify, [:ping_status, :status]) == "ok"
      assert File.exists?(get_in(verify, [:attach_status, :evidence_ref]))
      assert File.exists?(get_in(verify, [:registration_status, :evidence_ref]))
      assert File.exists?(get_in(verify, [:session_status, :evidence_ref]))
      assert File.exists?(get_in(verify, [:ping_status, :evidence_ref]))

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", verify_payload])
      assert capture.status == "captured"

      assert get_in(capture, [:bundle, :runtime, :simulation, :claim_scope]) ==
               "repo_local_simulation"

      assert get_in(capture, [:bundle, :runtime, :simulation, :attach]) =~ "attach.json"

      assert get_in(capture, [:bundle, :runtime, :simulation, :registration]) =~
               "registration.json"

      assert get_in(capture, [:bundle, :runtime, :simulation, :session]) =~ "session.json"
      assert get_in(capture, [:bundle, :runtime, :simulation, :ping]) =~ "ping.json"

      assert {:ok, %{status: "rolled_back"}} = CLI.run(["rollback", "--json", rollback_payload])
    end)
  end

  test "apply rejects runtime drift when current runtime metadata no longer matches the plan", %{
    tmp_dir: tmp_dir
  } do
    start_supervised!(RanActionGateway.MockDockerRunner)

    original_runner = Application.get_env(:ran_action_gateway, :command_runner)

    Application.put_env(
      :ran_action_gateway,
      :command_runner,
      RanActionGateway.MockDockerRunner,
      persistent: true
    )

    on_exit(fn ->
      Application.put_env(
        :ran_action_gateway,
        :command_runner,
        original_runner,
        persistent: true
      )
    end)

    runtime_fixture = build_runtime_fixture(tmp_dir)

    request =
      %{
        "approval" => approval_payload(),
        "metadata" => %{
          "oai_runtime" =>
            oai_runtime_payload(runtime_fixture, %{"project_name" => "test-oai-du"}),
          "runtime_contract" => runtime_contract_payload()
        }
      }
      |> then(&base_payload(&1))

    File.cd!(tmp_dir, fn ->
      payload = JSON.encode!(request)

      assert {:ok, %{status: "planned"}} = CLI.run(["plan", "--json", payload])

      drifted_payload =
        request
        |> put_in(["metadata", "oai_runtime", "project_name"], "test-oai-du-drift")
        |> JSON.encode!()

      assert {:error, %{status: "runtime_contract_mismatch", command: "apply", errors: errors}} =
               CLI.run(["apply", "--json", drifted_payload])

      assert Enum.any?(errors, &String.contains?(&1, "runtime_digest"))
    end)
  end

  @tag :runtime_contract
  test "oai runtime path optionally launches an OAI UE simulator", %{tmp_dir: tmp_dir} do
    start_supervised!(RanActionGateway.MockDockerRunner)

    original_runner = Application.get_env(:ran_action_gateway, :command_runner)

    Application.put_env(
      :ran_action_gateway,
      :command_runner,
      RanActionGateway.MockDockerRunner,
      persistent: true
    )

    on_exit(fn ->
      Application.put_env(
        :ran_action_gateway,
        :command_runner,
        original_runner,
        persistent: true
      )
    end)

    runtime_fixture = build_runtime_fixture(tmp_dir)

    payload =
      base_payload(%{
        "approval" => approval_payload(),
        "metadata" => %{
          "oai_runtime" =>
            oai_runtime_payload(runtime_fixture, %{
              "project_name" => "test-oai-du-ue",
              "ue_conf_path" => runtime_fixture.ue_conf_path
            }),
          "runtime_contract" => runtime_contract_payload()
        }
      })
      |> JSON.encode!()

    File.cd!(tmp_dir, fn ->
      assert {:ok, %{status: "ok", runtime: runtime}} = CLI.run(["precheck", "--json", payload])
      assert Enum.any?(runtime.checks, &(&1["name"] == "ue_conf_present"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "ue_image_present_or_pull_enabled"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "ue_tun_device_present"))
      assert Enum.any?(runtime.checks, &(&1["name"] == "ue_conf_declares_rfsimulator"))

      assert {:ok, plan} = CLI.run(["plan", "--json", payload])
      assert "oai-nr-ue" in plan["runtime_plan"].services
      assert "test-oai-du-ue-nr-ue" in plan["runtime_plan"].containers
      assert "oaisoftwarealliance/oai-nr-ue:develop" in Map.values(plan["runtime_plan"].images)

      compose = File.read!(plan["runtime_plan"].compose_path)
      assert compose =~ "oai-nr-ue:"
      assert compose =~ "/dev/net/tun:/dev/net/tun"
      assert compose =~ "--rfsimulator.[0].serveraddr oai-du"

      assert {:ok, apply} = CLI.run(["apply", "--json", payload])
      assert apply["runtime_result"].project_name == "test-oai-du-ue"

      assert {:ok, verify} = CLI.run(["verify", "--json", payload])
      assert Enum.any?(verify.checks, &(&1["name"] == "ue_log_started"))
      assert Enum.any?(verify.checks, &(&1["name"] == "ue_log_tun_configured"))
      assert File.exists?(Store.runtime_log_path("chg-test-001", "test-oai-du-ue-nr-ue"))

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", payload])
      assert length(capture.bundle.runtime.logs) == 4
      assert length(capture.bundle.runtime.configs) == 3
    end)
  end

  test "control state flows into verify, observe, rollback, and capture snapshots", %{
    tmp_dir: tmp_dir
  } do
    File.cd!(tmp_dir, fn ->
      apply_request =
        base_payload(%{
          "approval" => approval_payload(),
          "verify_window" => %{"duration" => "20s", "checks" => ["gateway_healthy"]},
          "metadata" => %{
            "control" => %{
              "attach_freeze" => "activate",
              "drain" => "start"
            }
          }
        })

      apply_payload = JSON.encode!(apply_request)

      assert {:ok, %{status: "planned"}} = CLI.run(["plan", "--json", apply_payload])

      assert {:ok, %{status: "applied", control_state: control_state}} =
               CLI.run(["apply", "--json", apply_payload])

      assert get_in(control_state, ["attach_freeze", "status"]) == "active"
      assert get_in(control_state, ["drain", "status"]) == "draining"

      verify_payload =
        apply_request
        |> Map.put("verify_window", %{
          "duration" => "20s",
          "checks" => ["attach_freeze_active", "drain_active"]
        })
        |> JSON.encode!()

      assert {:ok, %{status: "verified", control_state: verify_control_state} = verify} =
               CLI.run(["verify", "--json", verify_payload])

      assert Enum.any?(verify.checks, &(&1["name"] == "attach_freeze_active"))
      assert Enum.any?(verify.checks, &(&1["name"] == "drain_active"))
      assert get_in(verify_control_state, ["attach_freeze", "status"]) == "active"

      assert {:ok, observe} = CLI.run(["observe", "--json", apply_payload])
      assert observe.incident_summary.severity == "warning"
      assert "attach freeze is active" in observe.incident_summary.reasons
      assert "cell group drain workflow is active" in observe.incident_summary.reasons

      assert observe.incident_summary.suggested_next == [
               "release attach freeze after the maintenance window",
               "complete verify and clear drain when the cell group is stable"
             ]

      assert observe.config.release_readiness.status == :ok
      assert get_in(observe.control_state, ["drain", "status"]) == "draining"

      capture_payload =
        apply_request
        |> Map.put("incident_id", "inc-control-001")
        |> JSON.encode!()

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", capture_payload])
      assert capture.artifacts == [Store.capture_path("inc-control-001")]
      assert capture.bundle.manifest.ref == "inc-control-001"
      assert capture.bundle.manifest.change_id == "chg-test-001"
      assert capture.bundle.manifest.artifact_root == Store.artifact_root()
      assert capture.bundle.workflow.plan == Store.plan_path("chg-test-001")
      assert capture.bundle.workflow.change_state == Store.change_state_path("chg-test-001")
      assert capture.bundle.workflow.verify == Store.verify_path("chg-test-001")
      assert capture.bundle.workflow.rollback_plan == Store.rollback_plan_path("chg-test-001")
      assert capture.bundle.workflow.capture == Store.capture_path("inc-control-001")

      assert capture.bundle.workflow.approvals == [
               Store.approval_path("chg-test-001", "apply")
             ]

      assert capture.bundle.workflow.config_snapshot ==
               Store.config_snapshot_path("inc-control-001")

      assert capture.bundle.workflow.control_snapshot ==
               Store.control_snapshot_path("inc-control-001")

      assert capture.bundle.workflow.probe_snapshot == nil
      assert File.exists?(capture.bundle.workflow.config_snapshot)
      assert File.exists?(capture.bundle.workflow.control_snapshot)
      assert get_in(capture.bundle.control_state, ["attach_freeze", "status"]) == "active"

      rollback_payload =
        apply_request
        |> Map.put("approval", approval_payload())
        |> Map.put("metadata", %{
          "control" => %{
            "attach_freeze" => "release",
            "drain" => "clear"
          }
        })
        |> JSON.encode!()

      assert {:ok, %{status: "rolled_back", control_state: rollback_control_state}} =
               CLI.run(["rollback", "--json", rollback_payload])

      assert get_in(rollback_control_state, ["attach_freeze", "status"]) == "inactive"
      assert get_in(rollback_control_state, ["drain", "status"]) == "idle"
    end)
  end

  test "observe and capture surface native probe evidence from recent artifacts", %{
    tmp_dir: tmp_dir
  } do
    File.cd!(tmp_dir, fn ->
      Store.write_json(Store.verify_path("chg-test-001"), %{
        "status" => "failed",
        "command" => "verify",
        "change_id" => "chg-test-001",
        "runtime_result" => %{
          "backend_family" => "local_du_low",
          "worker_kind" => "local_du_low_contract_gateway",
          "strict_host_probe" => true,
          "activation_gate" => "strict",
          "handshake_target" => "netif:sync0 -> path:/dev/fh0",
          "probe_evidence_ref" => "probe-evidence://local_du_low/fh-test-001",
          "probe_checked_at" => "2026-03-22T12:00:00Z",
          "probe_required_resources" => ["netif:sync0", "path:/dev/fh0"],
          "probe_observations" => %{
            "host_interface" => %{"sysfs_path" => "/sys/class/net/sync0", "operstate" => "down"},
            "device_path" => %{"kind" => "char_device"}
          },
          "host_probe_ref" => "probe://local_du_low/fh-test-001",
          "host_probe_status" => "blocked",
          "host_probe_mode" => "strict_host_checks",
          "host_probe_failures" => ["missing_host_interface", "missing_device_path"],
          "probe_failure_count" => 2,
          "handshake_state" => "blocked"
        }
      })

      payload = JSON.encode!(base_payload(%{"incident_id" => "inc-probe-001"}))

      assert {:ok, observe} = CLI.run(["observe", "--json", payload])
      assert observe.summary =~ "native probe blocked"
      assert observe.native_probe.host_probe_status == "blocked"
      assert observe.native_probe.activation_gate == "strict"
      assert observe.native_probe.handshake_target == "netif:sync0 -> path:/dev/fh0"
      assert observe.native_probe.probe_required_resources == ["netif:sync0", "path:/dev/fh0"]
      assert observe.native_probe.probe_observations["host_interface"]["operstate"] == "down"
      assert "native host probe is blocked" in observe.incident_summary.reasons

      assert "restore native host resources: netif:sync0, path:/dev/fh0 / missing_host_interface, missing_device_path" in observe.incident_summary.suggested_next

      assert observe.incident_summary.native_probe.host_probe_failures == [
               "missing_host_interface",
               "missing_device_path"
             ]

      assert {:ok, capture} = CLI.run(["capture-artifacts", "--json", payload])
      assert capture.bundle.native_probe.host_probe_status == "blocked"
      assert capture.bundle.native_probe.handshake_target == "netif:sync0 -> path:/dev/fh0"

      assert capture.bundle.native_probe.probe_evidence_ref ==
               "probe-evidence://local_du_low/fh-test-001"

      assert File.exists?(capture.bundle.workflow.probe_snapshot)
    end)
  end

  test "precheck and verify run native probe checks when requested", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      File.mkdir_p!("artifacts")

      payload =
        base_payload(%{
          "approval" => approval_payload(),
          "metadata" => %{
            "native_probe" => %{
              "backend_profile" => "local_fapi_profile",
              "session_payload" => %{
                "fronthaul_session" => "fh-precheck-001",
                "host_interface" => "definitely-missing-iface",
                "strict_host_probe" => true
              }
            }
          }
        })
        |> JSON.encode!()

      assert {:ok, %{status: "failed", native_probe: native_probe, checks: checks}} =
               CLI.run(["precheck", "--json", payload])

      assert Map.get(native_probe, :host_probe_status, "blocked") == "blocked"
      assert native_probe.activation_status == "failed"

      assert Enum.any?(
               checks,
               &(&1["name"] == "native_probe_host_ready" and &1["status"] == "failed")
             )

      assert Enum.any?(
               checks,
               &(&1["name"] == "native_probe_activation_gate_clear" and &1["status"] == "failed")
             )

      File.cd!(tmp_dir)
      assert {:ok, %{status: "planned"}} = CLI.run(["plan", "--json", payload])
      File.cd!(tmp_dir)
      assert {:ok, %{status: "applied"}} = CLI.run(["apply", "--json", payload])

      File.cd!(tmp_dir)

      assert {:ok, %{status: "failed", native_probe: verify_probe, checks: verify_checks}} =
               CLI.run(["verify", "--json", payload])

      assert Map.get(verify_probe, :host_probe_status, "blocked") == "blocked"

      assert Enum.any?(
               verify_checks,
               &(&1["name"] == "native_probe_host_ready" and &1["status"] == "failed")
             )
    end)
  end

  defp base_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "scope" => "cell_group",
        "cell_group" => "cg-001",
        "target_backend" => "local_fapi_profile",
        "current_backend" => "stub_fapi_profile",
        "change_id" => "chg-test-001",
        "reason" => "switch backend in bootstrap test",
        "idempotency_key" => "chg-test-001-key",
        "dry_run" => false,
        "ttl" => "15m",
        "verify_window" => %{"duration" => "30s", "checks" => ["gateway_healthy"]},
        "max_blast_radius" => "single_cell_group"
      },
      overrides
    )
  end

  defp approval_payload do
    %{
      "approved" => true,
      "approved_by" => "bootstrap.operator",
      "approved_at" => "2026-03-21T00:00:00Z",
      "ticket_ref" => "CHG-BOOTSTRAP-001",
      "source" => "cli-test",
      "evidence" => ["docs/architecture/05-ranctl-action-model.md"]
    }
  end

  defp runtime_contract_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "version" => "ranctl.runtime.v1",
        "release_unit" => "bootstrap_source_bundle",
        "release_ref" => "source-checkout@cli-test",
        "entrypoint" => "bin/ranctl",
        "runtime_mode" => "docker_compose_rfsim_f1"
      },
      overrides
    )
  end

  defp oai_runtime_payload(runtime_fixture, overrides \\ %{}) do
    Map.merge(
      %{
        "repo_root" => runtime_fixture.repo_root,
        "du_conf_path" => runtime_fixture.du_conf_path,
        "cucp_conf_path" => runtime_fixture.cucp_conf_path,
        "cuup_conf_path" => runtime_fixture.cuup_conf_path,
        "project_name" => "test-oai-du",
        "pull_images" => false
      },
      overrides
    )
  end

  defp absolutize_public_oai_paths(request, repo_root) do
    request
    |> update_path_group(["metadata", "oai_runtime"], repo_root, [
      "repo_root",
      "du_conf_path",
      "cucp_conf_path",
      "cuup_conf_path"
    ])
    |> update_path_group(["metadata", "oai_simulation"], repo_root, [
      "ue_conf_path",
      "attach_evidence_path",
      "registration_evidence_path",
      "session_evidence_path",
      "ping_evidence_path"
    ])
  end

  defp update_path_group(request, path, repo_root, keys) do
    update_in(request, path, fn
      %{} = group ->
        Enum.reduce(keys, group, fn key, acc ->
          case acc[key] do
            value when is_binary(value) -> Map.put(acc, key, Path.expand(value, repo_root))
            _ -> acc
          end
        end)

      other ->
        other
    end)
  end

  defp build_runtime_fixture(tmp_dir) do
    repo_root = Path.join(tmp_dir, "openairinterface5g-fixture")
    conf_dir = Path.join(repo_root, "conf")
    File.mkdir_p!(conf_dir)

    du_conf_path = Path.join(conf_dir, "gnb-du.conf")
    cucp_conf_path = Path.join(conf_dir, "gnb-cucp.conf")
    cuup_conf_path = Path.join(conf_dir, "gnb-cuup.conf")
    ue_conf_path = Path.join(conf_dir, "nr-ue.conf")

    File.write!(
      du_conf_path,
      """
      MACRLCs = ({ tr_n_preference = "f1"; local_n_address = "192.168.71.171"; remote_n_address = "192.168.71.150"; });
      rfsimulator = ({});
      """
    )

    File.write!(
      cucp_conf_path,
      """
      gNBs = ({ tr_s_preference = "f1"; local_s_address = "192.168.71.150"; E1_INTERFACE = ({ ipv4_cucp = "192.168.71.150"; }); NETWORK_INTERFACES : { GNB_IPV4_ADDRESS_FOR_NG_AMF = "192.168.71.150/24"; }; });
      """
    )

    File.write!(
      cuup_conf_path,
      """
      gNBs = ({ gNB_CU_UP_ID = 0xe00; tr_s_preference = "f1"; local_s_address = "192.168.72.161"; remote_s_address = "192.168.72.171"; E1_INTERFACE = ({ ipv4_cucp = "192.168.71.150"; ipv4_cuup = "192.168.71.161"; }); NETWORK_INTERFACES : { GNB_IPV4_ADDRESS_FOR_NG_AMF = "192.168.71.161/24"; GNB_IPV4_ADDRESS_FOR_NGU = "192.168.71.161/24"; }; });
      """
    )

    File.write!(
      ue_conf_path,
      """
      uicc0 = {
        imsi = "001010000000001";
        key = "00112233445566778899aabbccddeeff";
        opc = "0102030405060708090a0b0c0d0e0f10";
        pdu_sessions = ({ dnn = "oai"; nssai_sst = 1; });
      }
      rfsimulator = ({ serveraddr = "127.0.0.1"; });
      """
    )

    %{
      repo_root: repo_root,
      du_conf_path: du_conf_path,
      cucp_conf_path: cucp_conf_path,
      cuup_conf_path: cuup_conf_path,
      ue_conf_path: ue_conf_path
    }
  end
end
