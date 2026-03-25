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
             "oaisoftwarealliance/oai-nr-cuup:develop"
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
        payload = path |> File.read!() |> JSON.decode!() |> JSON.encode!()
        result = CLI.run([command, "--json", payload])

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
      assert precheck.gate_class in ["blocked", "degraded"]

      assert get_in(precheck, [:core_link_status, :evidence_ref]) =~
               "artifacts/replacement/precheck/"

      assert get_in(precheck, [:interface_status, "ngap", :evidence_ref]) =~
               "artifacts/replacement/precheck/"

      verify_request =
        Path.join(
          repo_root,
          "subprojects/ran_replacement/examples/ranctl/verify-attach-ping-open5gs-n79.json"
        )
        |> File.read!()
        |> JSON.decode!()

      plan = %{
        "change_id" => verify_request["change_id"],
        "target_backend" => "replacement_shadow",
        "rollback_target" => "oai_reference",
        "runtime_contract" => nil,
        "verify_window" => verify_request["verify_window"]
      }

      state = %{
        "status" => "applied",
        "change_id" => verify_request["change_id"],
        "scope" => verify_request["scope"]
      }

      Store.write_json(Store.plan_path(verify_request["change_id"]), plan)
      Store.write_json(Store.change_state_path(verify_request["change_id"]), state)

      verify_payload = JSON.encode!(verify_request)
      assert {:ok, verify} = CLI.run(["verify", "--json", verify_payload])
      assert verify.core_profile == "open5gs_nsa_lab_v1"
      assert verify.gate_class in ["degraded", "pass"]

      assert get_in(verify, [:interface_status, "ngap", :evidence_ref]) =~
               "artifacts/replacement/verify/"

      assert get_in(verify, [:core_link_status, :evidence_ref]) =~ "artifacts/replacement/verify/"

      assert get_in(verify, [:attach_status, :evidence_ref]) =~
               "/attach.json"
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

      assert get_in(observe, [:interface_status, "ngap", :evidence_ref]) =~
               "artifacts/replacement/observe/"

      assert get_in(observe, [:core_link_status, :evidence_ref]) =~
               "artifacts/replacement/observe/"

      assert get_in(observe, [:attach_status, :evidence_ref]) =~
               "/attach.json"
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

      assert get_in(verify, [:interface_status, "ngap", :evidence_ref]) =~
               "artifacts/replacement/verify/"

      assert get_in(verify, [:core_link_status, :evidence_ref]) =~ "artifacts/replacement/verify/"

      assert get_in(verify, [:attach_status, :evidence_ref]) =~
               "/attach.json"
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

      assert native_probe.host_probe_status == "blocked"
      assert native_probe.activation_status == "failed"

      assert Enum.any?(
               checks,
               &(&1["name"] == "native_probe_host_ready" and &1["status"] == "failed")
             )

      assert Enum.any?(
               checks,
               &(&1["name"] == "native_probe_activation_gate_clear" and &1["status"] == "failed")
             )

      assert {:ok, %{status: "planned"}} = CLI.run(["plan", "--json", payload])
      assert {:ok, %{status: "applied"}} = CLI.run(["apply", "--json", payload])

      assert {:ok, %{status: "failed", native_probe: verify_probe, checks: verify_checks}} =
               CLI.run(["verify", "--json", payload])

      assert verify_probe.host_probe_status == "blocked"

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

  defp build_runtime_fixture(tmp_dir) do
    repo_root = Path.join(tmp_dir, "openairinterface5g-fixture")
    conf_dir = Path.join(repo_root, "conf")
    File.mkdir_p!(conf_dir)

    du_conf_path = Path.join(conf_dir, "gnb-du.conf")
    cucp_conf_path = Path.join(conf_dir, "gnb-cucp.conf")
    cuup_conf_path = Path.join(conf_dir, "gnb-cuup.conf")

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

    %{
      repo_root: repo_root,
      du_conf_path: du_conf_path,
      cucp_conf_path: cucp_conf_path,
      cuup_conf_path: cuup_conf_path
    }
  end
end
