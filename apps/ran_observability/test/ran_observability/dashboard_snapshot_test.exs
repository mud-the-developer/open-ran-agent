defmodule RanObservability.MockCommandRunner do
  @behaviour RanObservability.CommandRunner

  @impl true
  def run("docker", ["ps", "-a", "--format", "{{json .}}"], _opts) do
    lines = [
      %{
        "Names" => "ran-oai-we-flexric-rfsim-local-001",
        "Image" => "oaisoftwarealliance/oai-gnb:develop",
        "State" => "running",
        "Status" => "Up 10 minutes",
        "RunningFor" => "10 minutes ago",
        "Networks" => "host",
        "Ports" => "",
        "Labels" => "com.docker.compose.project=ran-oai,we=true"
      },
      %{
        "Names" => "nearRT-RIC",
        "Image" => "oai-flexric:dev",
        "State" => "running",
        "Status" => "Up 3 weeks",
        "RunningFor" => "3 weeks ago",
        "Networks" => "oai-e2-net",
        "Ports" => "0.0.0.0:36421->36421/sctp",
        "Labels" => "com.docker.compose.project=docker,com.docker.compose.service=nearRT-RIC"
      }
    ]

    {Enum.map_join(lines, "\n", &JSON.encode!/1), 0}
  end
end

defmodule RanObservability.MockCliRunner do
  @behaviour RanObservability.CommandRunner

  @impl true
  def run(command, ["observe", "--json", _payload], _opts) do
    if String.ends_with?(command, "/bin/ranctl") do
      {JSON.encode!(%{"status" => "observed", "command" => "observe"}), 0}
    else
      {JSON.encode!(%{"status" => "invalid_command"}), 1}
    end
  end
end

defmodule RanObservability.MockCliRunnerWithLogs do
  @behaviour RanObservability.CommandRunner

  @impl true
  def run(command, ["apply", "--json", _payload], _opts) do
    if String.ends_with?(command, "/bin/ranctl") do
      {"15:49:38.606 [info] ranctl apply starting\n" <>
         ~s({"status":"applied","command":"apply","change_id":"chg-dashboard-apply-001"}), 0}
    else
      {JSON.encode!(%{"status" => "invalid_command"}), 1}
    end
  end
end

defmodule RanObservability.MockWizardRunner do
  @behaviour RanObservability.CommandRunner

  @impl true
  def run(command, args, _opts) do
    if String.ends_with?(command, "/bin/ran-deploy-wizard") do
      payload = %{
        "status" => "configured",
        "mode" => "defaults",
        "install_performed" => false,
        "bundle_tarball" => "artifacts/releases/mock/open_ran_agent-mock.tar.gz",
        "current_root" => "/tmp/open-ran-agent/current",
        "etc_root" => "/tmp/open-ran-agent/etc",
        "files" => %{
          "topology_path" => "/tmp/open-ran-agent/etc/topology.single_du.target_host.rfsim.json",
          "request_path" => "/tmp/open-ran-agent/etc/requests/precheck-target-host.json",
          "dashboard_env_path" => "/tmp/open-ran-agent/etc/ran-dashboard.env",
          "preflight_env_path" => "/tmp/open-ran-agent/etc/ran-host-preflight.env",
          "profile_path" => "/tmp/open-ran-agent/etc/deploy.profile.json",
          "effective_config_path" => "/tmp/open-ran-agent/etc/deploy.effective.json",
          "readiness_path" => "/tmp/open-ran-agent/etc/deploy.readiness.json"
        },
        "previews" => %{
          "topology" => %{
            "path" => "/tmp/open-ran-agent/etc/topology.single_du.target_host.rfsim.json",
            "content" => ~s({"repo_profile":"prod_target_host_rfsim"})
          },
          "request" => %{
            "path" => "/tmp/open-ran-agent/etc/requests/precheck-target-host.json",
            "content" => ~s({"scope":"cell_group"})
          },
          "dashboard_env" => %{
            "path" => "/tmp/open-ran-agent/etc/ran-dashboard.env",
            "content" => "RAN_DASHBOARD_PORT=4050\n"
          },
          "preflight_env" => %{
            "path" => "/tmp/open-ran-agent/etc/ran-host-preflight.env",
            "content" =>
              "RAN_PREFLIGHT_REQUEST=/tmp/open-ran-agent/etc/requests/precheck-target-host.json\n"
          },
          "profile_manifest" => %{
            "path" => "/tmp/open-ran-agent/etc/deploy.profile.json",
            "content" => ~s({"name":"stable_ops","title":"Stable Ops"})
          },
          "effective_config" => %{
            "path" => "/tmp/open-ran-agent/etc/deploy.effective.json",
            "content" => ~s({"deploy_profile":{"name":"stable_ops"}})
          },
          "readiness" => %{
            "path" => "/tmp/open-ran-agent/etc/deploy.readiness.json",
            "content" =>
              ~s({"status":"ready_for_preflight","recommendation":"run_preflight","score":80})
          }
        },
        "readiness" => %{
          "status" => "ready_for_preflight",
          "recommendation" => "run_preflight",
          "score" => 80,
          "summary" =>
            "Stable Ops is staged for the target host. Run preflight to clear the final gate."
        },
        "handoff" => %{
          "enabled" => true,
          "ssh_target" => "ranops@ran-lab-01",
          "commands" => [
            "scp -P '2222' '/tmp/bundle.tar.gz' 'ranops@ran-lab-01:/tmp/open-ran-agent/bundle.tar.gz'",
            "ssh -p '2222' 'ranops@ran-lab-01' '/opt/open-ran-agent/current/bin/ran-host-preflight'"
          ]
        },
        "next_steps" => ["ship bundle", "run preflight"],
        "preflight" =>
          if("--run-precheck" in args,
            do: %{"status" => "ok", "output" => "host ready\n"},
            else: nil
          )
      }

      {"wizard log line\n" <> JSON.encode!(payload), 0}
    else
      {JSON.encode!(%{"status" => "invalid_command"}), 1}
    end
  end
end

defmodule RanObservability.DashboardSnapshotTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias RanObservability.Dashboard.Snapshot
  alias RanObservability.Dashboard.Router

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-dashboard-#{System.unique_integer([:positive, :monotonic])}"
      )

    artifacts = Path.join(tmp_dir, "artifacts")
    skills = Path.join(tmp_dir, "skills")

    File.mkdir_p!(Path.join(artifacts, "plans"))
    File.mkdir_p!(Path.join(artifacts, "observations"))
    File.mkdir_p!(Path.join(artifacts, "verify"))
    File.mkdir_p!(Path.join(artifacts, "control_state"))
    File.mkdir_p!(Path.join(artifacts, "runtime/demo"))
    File.mkdir_p!(Path.join(artifacts, "releases/bootstrap-ui-001"))
    File.mkdir_p!(Path.join(artifacts, "deploy_preview/quick_install/20260323T095333"))
    File.mkdir_p!(Path.join(artifacts, "install_runs/ran-lab-02/20260323T105012-ship"))

    File.mkdir_p!(
      Path.join(artifacts, "remote_runs/ran-lab-01/20260323T005029-precheck/fetch/extracted")
    )

    File.mkdir_p!(Path.join(skills, "ran-observe/scripts"))
    File.mkdir_p!(Path.join(skills, "ran-observe/references"))

    File.write!(
      Path.join(artifacts, "observations/chg-oai-observe-001.json"),
      JSON.encode!(%{
        "status" => "observed",
        "command" => "observe",
        "scope" => "cell_group",
        "cell_group" => "cg-001",
        "change_id" => "chg-oai-observe-001",
        "summary" => "repo-local OAI observe captured runtime state",
        "runtime" => %{
          "lane_id" => "oai_split_rfsim_repo_local_v1",
          "runtime_mode" => "docker_compose_rfsim_f1",
          "project_name" => "ran-oai-du-local-rfsim",
          "runtime_state" => "running",
          "service_count" => 3,
          "running_service_count" => 3,
          "healthy_service_count" => 3,
          "containers" => [
            %{
              "name" => "ran-oai-du-local-rfsim-cucp",
              "role" => "cucp",
              "service_name" => "oai-cucp",
              "running" => true,
              "status" => "running",
              "health" => "healthy",
              "log_probe_status" => "ok",
              "log_tail_line_count" => 1,
              "token_counts" => %{"cucp_f1_setup_response_count" => 1}
            },
            %{
              "name" => "ran-oai-du-local-rfsim-cuup",
              "role" => "cuup",
              "service_name" => "oai-cuup",
              "running" => true,
              "status" => "running",
              "health" => "healthy",
              "log_probe_status" => "ok",
              "log_tail_line_count" => 1,
              "token_counts" => %{"cuup_e1_established_count" => 1}
            },
            %{
              "name" => "ran-oai-du-local-rfsim-du",
              "role" => "du",
              "service_name" => "oai-du",
              "running" => true,
              "status" => "running",
              "health" => "healthy",
              "log_probe_status" => "ok",
              "log_tail_line_count" => 2,
              "token_counts" => %{
                "du_frame_slot_count" => 2,
                "du_f1_setup_response_count" => 0,
                "du_rfsim_wait_count" => 0
              }
            }
          ],
          "token_metrics" => [
            %{
              "id" => "du_frame_slot_count",
              "label" => "DU Frame.Slot tokens",
              "count" => 2,
              "role" => "du",
              "container_name" => "ran-oai-du-local-rfsim-du",
              "source_kind" => "docker_logs_tail",
              "source_pattern" => "Frame.Slot",
              "source_tail_lines" => 2000,
              "meaning" => "Counts DU MAC slot-loop tokens in the current Docker log tail."
            },
            %{
              "id" => "cucp_f1_setup_response_count",
              "label" => "CU-CP F1 setup responses",
              "count" => 1,
              "role" => "cucp",
              "container_name" => "ran-oai-du-local-rfsim-cucp",
              "source_kind" => "docker_logs_tail",
              "source_pattern" => "sending F1 Setup Response",
              "source_tail_lines" => 2000,
              "meaning" =>
                "Counts CU-CP log tokens proving the split control plane answered the DU F1 setup."
            }
          ]
        }
      })
    )

    File.write!(
      Path.join(artifacts, "plans/chg-ui-001.json"),
      JSON.encode!(%{
        "command" => "plan",
        "status" => "planned",
        "change_id" => "chg-ui-001",
        "scope" => "cell_group",
        "target_backend" => "local_fapi_profile"
      })
    )

    File.write!(
      Path.join(artifacts, "control_state/cg-001.json"),
      JSON.encode!(%{
        "cell_group" => "cg-001",
        "attach_freeze" => %{
          "status" => "active",
          "reason" => "maintenance-window",
          "source_change_id" => "chg-control-001",
          "source_command" => "apply",
          "changed_at" => "2026-03-22T09:54:58Z"
        },
        "drain" => %{
          "status" => "draining",
          "reason" => "operator-maintenance",
          "source_change_id" => "chg-control-001",
          "source_command" => "apply",
          "changed_at" => "2026-03-22T09:54:59Z"
        },
        "updated_at" => "2026-03-22T09:54:59Z"
      })
    )

    File.write!(Path.join(artifacts, "runtime/demo/runtime.log"), "line-1\nline-2\nline-3\n")

    File.write!(
      Path.join(artifacts, "verify/chg-contract-001.json"),
      JSON.encode!(%{
        "command" => "verify",
        "status" => "verified",
        "change_id" => "chg-contract-001",
        "scope" => "cell_group",
        "target_backend" => "local_du_low_profile",
        "runtime_result" => %{
          "backend_family" => "local_du_low",
          "worker_kind" => "transport_worker",
          "transport_worker" => "fapi_rt_gateway",
          "execution_lane" => "slot_executor",
          "dispatch_mode" => "slot_batch",
          "transport_mode" => "port",
          "policy_mode" => "quiesced",
          "accepted_profile" => "local_du_low_profile",
          "fronthaul_session" => "cg-001/f1",
          "device_session_ref" => "local_du_low://cg-001/f1/device_session",
          "device_session_state" => "draining",
          "device_generation" => 42,
          "device_profile" => "fronthaul_loopback",
          "policy_surface_ref" => "policy://local/cg-001",
          "handshake_ref" => "local_du_low://cg-001/f1/handshake",
          "handshake_state" => "draining",
          "handshake_attempts" => 2,
          "last_handshake_at" => "2026-03-22T09:55:02Z",
          "strict_host_probe" => true,
          "activation_gate" => "strict",
          "handshake_target" => "netif:sync0 -> path:/dev/fh0",
          "probe_evidence_ref" => "probe-evidence://local_du_low/cg-001/f1",
          "probe_checked_at" => "2026-03-22T09:55:01Z",
          "probe_required_resources" => ["netif:sync0", "path:/dev/fh0"],
          "probe_observations" => %{
            "host_interface" => %{"sysfs_path" => "/sys/class/net/sync0", "operstate" => "down"},
            "device_path" => %{"kind" => "char_device"}
          },
          "host_probe_ref" => "probe://local_du_low/cg-001/f1",
          "host_probe_status" => "ready",
          "host_probe_mode" => "loopback",
          "host_probe_failures" => ["missing_device_path"],
          "health" => %{
            "status" => "healthy",
            "checks" => [
              %{"name" => "transport_worker", "status" => "passed"},
              %{"name" => "execution_lane", "status" => "passed"}
            ]
          },
          "signals" => %{
            "uplink_ring_depth" => 8,
            "batch_window_us" => 500,
            "slot_budget_us" => 800,
            "last_uplink_kind" => "phy.indication"
          },
          "session" => %{
            "epoch" => 7,
            "started_at" => "2026-03-22T09:55:00Z",
            "last_submit_at" => "2026-03-22T09:55:03Z",
            "last_uplink_at" => "2026-03-22T09:55:04Z",
            "last_resume_at" => "2026-03-22T09:55:05Z",
            "drain" => %{
              "state" => "draining",
              "reason" => "operator-maintenance"
            },
            "queue" => %{"depth" => 4},
            "timing" => %{
              "window_us" => 500,
              "budget_us" => 800,
              "deadline_miss_count" => 2
            }
          }
        }
      })
    )

    File.write!(
      Path.join(artifacts, "deploy_preview/quick_install/20260323T095333/debug-summary.txt"),
      "kind=quick_install\n" <>
        "run_stamp=20260323T095333\n" <>
        "target_host=ran-lab-01\n" <>
        "deploy_profile=stable_ops\n" <>
        "readiness_status=ready_for_preflight\n" <>
        "readiness_score=80\n" <>
        "recommendation=run_preflight\n" <>
        "status=prepared\n"
    )

    File.write!(
      Path.join(artifacts, "deploy_preview/quick_install/20260323T095333/INSTALL.md"),
      "# install\n"
    )

    File.write!(
      Path.join(artifacts, "deploy_preview/quick_install/20260323T095333/install.preview.sh"),
      "#!/usr/bin/env bash\n"
    )

    File.write!(
      Path.join(artifacts, "install_runs/ran-lab-02/20260323T105012-ship/debug-summary.txt"),
      "kind=ship_bundle\n" <>
        "run_stamp=20260323T105012\n" <>
        "target_host=ran-lab-02\n" <>
        "deploy_profile=stable_ops\n" <>
        "plan_file=/tmp/ship/plan.txt\n" <>
        "transcript_file=/tmp/ship/transcript.log\n" <>
        "debug_pack_file=/tmp/ship/debug-pack.txt\n" <>
        "failed_step=remote_preflight\n" <>
        "failed_command=ssh -p 22 ranops@ran-lab-02 /opt/open-ran-agent/current/bin/ran-host-preflight\n" <>
        "exit_code=255\n" <>
        "status=failed\n"
    )

    File.write!(
      Path.join(artifacts, "install_runs/ran-lab-02/20260323T105012-ship/debug-pack.txt"),
      "Debug Pack\n  kind       : ship_bundle\n"
    )

    File.write!(
      Path.join(artifacts, "install_runs/ran-lab-02/20260323T105012-ship/plan.txt"),
      "Remote handoff plan\n"
    )

    File.write!(
      Path.join(artifacts, "install_runs/ran-lab-02/20260323T105012-ship/transcript.log"),
      "+ ssh ranops@ran-lab-02 /opt/open-ran-agent/current/bin/ran-host-preflight\n" <>
        "ssh: connect to host ran-lab-02 port 22: No route to host\n"
    )

    File.write!(
      Path.join(artifacts, "releases/bootstrap-ui-001/manifest.json"),
      JSON.encode!(%{
        "status" => "packaged",
        "bundle_id" => "bootstrap-ui-001",
        "release_unit" => "bootstrap_source_bundle",
        "tarball_path" => "/tmp/bootstrap-ui-001.tar.gz",
        "profile" => "bootstrap"
      })
    )

    File.write!(
      Path.join(artifacts, "remote_runs/ran-lab-01/20260323T005029-precheck/plan.txt"),
      "Remote ranctl plan\n  command     : precheck\n"
    )

    File.write!(
      Path.join(artifacts, "remote_runs/ran-lab-01/20260323T005029-precheck/result.jsonl"),
      "2026-03-23T00:50:29Z remote precheck\n" <>
        ~s({"status":"ok","command":"precheck","change_id":"chg-target-host-001"})
    )

    File.write!(
      Path.join(
        artifacts,
        "remote_runs/ran-lab-01/20260323T005029-precheck/fetch/extracted/fetch-summary.txt"
      ),
      "target_host=ran-lab-01\n" <>
        "change_id=chg-target-host-001\n" <>
        "cell_group=cg-001\n" <>
        "copied_entries=4\n"
    )

    File.write!(Path.join(skills, "ran-observe/SKILL.md"), "# skill\n")
    File.write!(Path.join(skills, "ran-observe/scripts/run.sh"), "#!/usr/bin/env bash\n")
    File.write!(Path.join(skills, "ran-observe/references/REQUESTS.md"), "# refs\n")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{artifacts: artifacts, skills: skills}
  end

  test "snapshot merges runtime, skills, and recent activity", %{
    artifacts: artifacts,
    skills: skills
  } do
    snapshot =
      Snapshot.build(
        artifact_root: artifacts,
        skills_root: skills,
        command_runner: RanObservability.MockCommandRunner
      )

    assert snapshot.overview.ran_runtime_count == 1
    assert snapshot.overview.agent_runtime_count == 1
    assert snapshot.overview.oai_observation_count == 1
    assert snapshot.overview.recent_bundle_count == 1
    assert snapshot.overview.remote_run_count == 1
    assert snapshot.overview.install_run_count == 2
    assert snapshot.overview.debug_failure_count == 1
    assert snapshot.overview.prune_candidate_count == 0
    assert snapshot.overview.native_contract_count == 1
    assert snapshot.overview.proof_surface_count == 1
    assert snapshot.overview.documented_counter_count == 8
    assert snapshot.overview.claim_surface_count == 2
    assert snapshot.overview.replay_drilldown_count == 4
    assert [%{name: "ran-observe"}] = snapshot.agents.skills

    assert Enum.any?(
             snapshot.activity.recent_changes,
             &(&1.id == "chg-ui-001" and &1.command == "plan")
           )

    assert Enum.any?(
             snapshot.activity.native_contract_runs,
             &(&1.id == "chg-contract-001" and &1.backend_family == "local_du_low" and
                 &1.worker_kind == "transport_worker" and
                 &1.transport_worker == "fapi_rt_gateway" and
                 &1.execution_lane == "slot_executor" and &1.health_status == "healthy" and
                 &1.device_session_ref == "local_du_low://cg-001/f1/device_session" and
                 &1.device_session_state == "draining" and &1.device_generation == 42 and
                 &1.device_profile == "fronthaul_loopback" and
                 &1.policy_surface_ref == "policy://local/cg-001" and
                 &1.handshake_ref == "local_du_low://cg-001/f1/handshake" and
                 &1.handshake_state == "draining" and &1.handshake_attempts == 2 and
                 &1.last_handshake_at == "2026-03-22T09:55:02Z" and
                 &1.strict_host_probe == true and
                 &1.activation_gate == "strict" and
                 &1.handshake_target == "netif:sync0 -> path:/dev/fh0" and
                 &1.probe_evidence_ref == "probe-evidence://local_du_low/cg-001/f1" and
                 &1.probe_checked_at == "2026-03-22T09:55:01Z" and
                 &1.probe_required_resources == ["netif:sync0", "path:/dev/fh0"] and
                 &1.probe_observations["host_interface"]["operstate"] == "down" and
                 &1.host_probe_ref == "probe://local_du_low/cg-001/f1" and
                 &1.host_probe_status == "ready" and &1.host_probe_mode == "loopback" and
                 &1.host_probe_failures == ["missing_device_path"] and
                 &1.session_epoch == 7 and &1.session_started_at == "2026-03-22T09:55:00Z" and
                 &1.last_submit_at == "2026-03-22T09:55:03Z" and
                 &1.last_uplink_at == "2026-03-22T09:55:04Z" and
                 &1.last_resume_at == "2026-03-22T09:55:05Z" and
                 &1.queue_depth == 4 and &1.drain_state == "draining" and
                 &1.drain_reason == "operator-maintenance" and &1.deadline_miss_count == 2 and
                 &1.timing_window_us == 500 and &1.timing_budget_us == 800)
           )

    assert [
             %{
               id: "chg-contract-001",
               backend_family: "local_du_low",
               worker_kind: "transport_worker",
               device_session_ref: "local_du_low://cg-001/f1/device_session",
               device_session_state: "draining",
               device_generation: 42,
               device_profile: "fronthaul_loopback",
               policy_surface_ref: "policy://local/cg-001",
               handshake_ref: "local_du_low://cg-001/f1/handshake",
               handshake_state: "draining",
               handshake_attempts: 2,
               last_handshake_at: "2026-03-22T09:55:02Z",
               strict_host_probe: true,
               activation_gate: "strict",
               handshake_target: "netif:sync0 -> path:/dev/fh0",
               probe_evidence_ref: "probe-evidence://local_du_low/cg-001/f1",
               probe_checked_at: "2026-03-22T09:55:01Z",
               probe_required_resources: ["netif:sync0", "path:/dev/fh0"],
               probe_observations: %{
                 "host_interface" => %{
                   "operstate" => "down",
                   "sysfs_path" => "/sys/class/net/sync0"
                 },
                 "device_path" => %{"kind" => "char_device"}
               },
               host_probe_ref: "probe://local_du_low/cg-001/f1",
               host_probe_status: "ready",
               host_probe_mode: "loopback",
               host_probe_failures: ["missing_device_path"],
               session_epoch: 7,
               session_started_at: "2026-03-22T09:55:00Z",
               last_submit_at: "2026-03-22T09:55:03Z",
               last_uplink_at: "2026-03-22T09:55:04Z",
               last_resume_at: "2026-03-22T09:55:05Z",
               queue_depth: 4,
               drain_state: "draining",
               drain_reason: "operator-maintenance",
               deadline_miss_count: 2,
               timing_window_us: 500,
               timing_budget_us: 800
             }
           ] = snapshot.runtime.native_contracts

    assert [%{name: "runtime.log"}] = snapshot.runtime.evidence
    assert [%{bundle_id: "bootstrap-ui-001"}] = snapshot.release.recent_bundles
    assert [%{cell_group: "cg-001", runtime_state: "running"}] = snapshot.ran.oai_repo_local_lanes
    assert length(snapshot.ran.claim_surfaces) == 2

    assert Enum.any?(snapshot.ran.cell_groups, fn group ->
             group.id == "cg-001" and
               group.oai_observation.project_name == "ran-oai-du-local-rfsim" and
               group.oai_observation.runtime_state == "running" and
               group.oai_observation.token_metric_count == 2 and
               length(group.oai_observation.containers) == 3 and
               group.control_state_ref =~ "control_state/cg-001.json" and
               group.latest_native_contract.id == "chg-contract-001" and
               group.proof_surface.summary.lane_count == 6 and
               group.proof_surface.summary.protocol_count == 7 and
               group.proof_surface.summary.counter_count == 8 and
               group.proof_surface.summary.claim_count == 2 and
               group.proof_surface.summary.replay_count == 4
           end)

    assert Enum.any?(snapshot.ran.cell_groups, fn group ->
             Enum.any?(group.proof_surface.protocol_state, fn field ->
               field.id == "attach_freeze" and field.value == "active" and
                 field.source_ref =~ "control_state/cg-001.json"
             end)
           end)

    assert Enum.any?(snapshot.ran.cell_groups, fn group ->
             Enum.any?(group.proof_surface.counter_provenance, fn counter ->
               counter.id == "cucp_f1_setup_response_count" and
                 counter.source_ref =~ "observations/chg-oai-observe-001.json" and
                 counter.source_pattern == "sending F1 Setup Response"
             end)
           end)

    assert Enum.any?(snapshot.ran.cell_groups, fn group ->
             Enum.any?(group.proof_surface.claims, fn claim ->
               claim.id == "repo_local_oai_rfsim_rehearsal_lane" and claim.status == "running" and
                 Enum.any?(
                   claim.current_refs,
                   &String.contains?(&1.path, "chg-oai-observe-001.json")
                 )
             end)
           end)

    assert Enum.any?(snapshot.ran.cell_groups, fn group ->
             Enum.any?(group.proof_surface.replay_drilldowns, fn drilldown ->
               drilldown.id == "remote_fetchback" and
                 Enum.any?(
                   drilldown.refs,
                   &String.contains?(&1.path || "", "/remote_runs/ran-lab-01/")
                 )
             end)
           end)

    assert [%{host: "ran-lab-01", command: "precheck", fetch_status: "fetched"}] =
             snapshot.deploy.recent_remote_runs

    assert Enum.any?(
             snapshot.deploy.recent_install_runs,
             &(&1.kind == "quick_install" and &1.host == "ran-lab-01" and
                 &1.deploy_profile == "stable_ops" and
                 &1.readiness_status == "ready_for_preflight" and
                 &1.readiness_score == 80 and &1.status == "prepared")
           )

    assert snapshot.debug.latest_failure.kind == "ship_bundle"
    assert snapshot.debug.latest_failure.status == "failed"
    assert snapshot.debug.latest_failure.host == "ran-lab-02"
    assert snapshot.debug.latest_failure.failed_step == "remote_preflight"
    assert snapshot.debug.latest_failure.exit_code == 255
    assert snapshot.deploy.latest_debug_incident.status == "failed"
    assert snapshot.deploy.recent_debug_failure_count == 1

    assert snapshot.release.readiness.status in ["ok", "error"]
    assert snapshot.retention.summary.prune_count == 0
    assert snapshot.deploy.status == "ok"
    assert snapshot.deploy.recent_remote_run_count == 1
    assert snapshot.deploy.recent_install_run_count == 2
    assert snapshot.deploy.defaults.strict_host_probe == true
    assert snapshot.deploy.defaults.deploy_profile == "stable_ops"
    assert Enum.any?(snapshot.deploy.profile_catalog, &(&1.name == "stable_ops"))
    assert Enum.any?(snapshot.deploy.profile_catalog, &(&1.stability_tier == "conservative"))
    assert snapshot.deploy.safe_preview_root =~ "artifacts/deploy_preview"
  end

  test "router serves dashboard health endpoint" do
    {status, content_type, body} = Router.response_for("GET", "/api/health", "")
    assert status == 200
    assert content_type =~ "application/json"
    assert body =~ "\"status\":\"ok\""
  end

  test "router serves deploy defaults endpoint" do
    {status, content_type, body} = Router.response_for("GET", "/api/deploy/defaults", "")

    assert status == 200
    assert content_type =~ "application/json"
    assert {:ok, decoded} = JSON.decode(body)
    assert decoded["status"] == "ok"
    assert decoded["safe_preview_root"] =~ "artifacts/deploy_preview"
    assert decoded["defaults"]["strict_host_probe"] == true
    assert decoded["defaults"]["deploy_profile"] == "stable_ops"
    assert Enum.any?(decoded["profile_catalog"], &(&1["name"] == "stable_ops"))
    assert Enum.any?(decoded["profile_catalog"], &(&1["stability_tier"] == "conservative"))
    assert "review-readiness" in decoded["recommended_actions"]
    assert "handoff" in decoded["recommended_actions"]
  end

  test "router executes dashboard action endpoint", %{artifacts: artifacts} do
    original_runner = Application.get_env(:ran_observability, :dashboard_command_runner)

    Application.put_env(
      :ran_observability,
      :dashboard_command_runner,
      RanObservability.MockCliRunner
    )

    on_exit(fn ->
      Application.put_env(
        :ran_observability,
        :dashboard_command_runner,
        original_runner
      )
    end)

    File.cd!(Path.dirname(artifacts), fn ->
      payload =
        JSON.encode!(%{
          "command" => "observe",
          "scope" => "cell_group",
          "cell_group" => "cg-001",
          "change_id" => "chg-dashboard-observe-001",
          "reason" => "observe from dashboard test",
          "idempotency_key" => "observe-dashboard-001",
          "verify_window" => %{"duration" => "30s", "checks" => ["gateway_healthy"]}
        })

      {status, content_type, body} = Router.response_for("POST", "/api/actions/run", payload)

      assert status == 200
      assert content_type =~ "application/json"

      assert {:ok, decoded} = JSON.decode(body)
      assert decoded["status"] == "ok"
      assert decoded["command"] == "observe"
      assert decoded["result"]["status"] == "observed"
    end)
  end

  test "router decodes trailing JSON payloads for noisy action output", %{artifacts: artifacts} do
    original_runner = Application.get_env(:ran_observability, :dashboard_command_runner)

    Application.put_env(
      :ran_observability,
      :dashboard_command_runner,
      RanObservability.MockCliRunnerWithLogs
    )

    on_exit(fn ->
      Application.put_env(
        :ran_observability,
        :dashboard_command_runner,
        original_runner
      )
    end)

    File.cd!(Path.dirname(artifacts), fn ->
      payload =
        JSON.encode!(%{
          "command" => "apply",
          "scope" => "cell_group",
          "cell_group" => "cg-001",
          "target_backend" => "local_fapi_profile",
          "current_backend" => "stub_fapi_profile",
          "change_id" => "chg-dashboard-apply-001",
          "reason" => "apply from dashboard test",
          "idempotency_key" => "apply-dashboard-001",
          "verify_window" => %{"duration" => "30s", "checks" => ["gateway_healthy"]},
          "approval" => %{
            "approved" => true,
            "approved_by" => "dashboard.operator",
            "approved_at" => "2026-03-21T00:00:00Z",
            "ticket_ref" => "DASH-APPLY-001",
            "source" => "dashboard"
          }
        })

      {status, content_type, body} = Router.response_for("POST", "/api/actions/run", payload)

      assert status == 200
      assert content_type =~ "application/json"

      assert {:ok, decoded} = JSON.decode(body)
      assert decoded["status"] == "ok"
      assert decoded["command"] == "apply"
      assert decoded["result"]["status"] == "applied"
    end)
  end

  test "router executes deploy preview and preflight endpoints" do
    original_runner = Application.get_env(:ran_observability, :dashboard_command_runner)

    Application.put_env(
      :ran_observability,
      :dashboard_command_runner,
      RanObservability.MockWizardRunner
    )

    on_exit(fn ->
      Application.put_env(
        :ran_observability,
        :dashboard_command_runner,
        original_runner
      )
    end)

    preview_payload =
      JSON.encode!(%{
        "mode" => "preview",
        "config" => %{
          "cell_group" => "cg-deploy-ui",
          "host_interface" => "sync0",
          "device_path" => "/dev/fh0"
        }
      })

    {preview_status, preview_type, preview_body} =
      Router.response_for("POST", "/api/deploy/run", preview_payload)

    assert preview_status == 200
    assert preview_type =~ "application/json"
    assert {:ok, preview_decoded} = JSON.decode(preview_body)
    assert preview_decoded["status"] == "ok"
    assert preview_decoded["mode"] == "preview"
    assert preview_decoded["config"]["cell_group"] == "cg-deploy-ui"
    assert preview_decoded["result"]["status"] == "configured"
    assert preview_decoded["result"]["readiness"]["status"] == "ready_for_preflight"
    assert preview_decoded["result"]["previews"]["readiness"]["content"] =~ "run_preflight"
    assert preview_decoded["result"]["previews"]["topology"]["content"] =~ "repo_profile"
    assert preview_decoded["result"]["handoff"]["ssh_target"] == "ranops@ran-lab-01"

    assert Enum.any?(
             preview_decoded["result"]["handoff"]["commands"],
             &String.contains?(&1, "ran-host-preflight")
           )

    preflight_payload =
      JSON.encode!(%{
        "mode" => "preflight",
        "config" => %{
          "cell_group" => "cg-deploy-ui",
          "host_interface" => "sync0"
        }
      })

    {preflight_status, _, preflight_body} =
      Router.response_for("POST", "/api/deploy/run", preflight_payload)

    assert preflight_status == 200
    assert {:ok, preflight_decoded} = JSON.decode(preflight_body)
    assert preflight_decoded["mode"] == "preflight"
    assert preflight_decoded["result"]["preflight"]["status"] == "ok"
    assert preflight_decoded["result"]["preflight"]["output"] =~ "host ready"
  end

  test "system command runner keeps stderr out of JSON payloads" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-dashboard-runner-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)
    script_path = Path.join(tmp_dir, "emit_json.sh")

    File.write!(
      script_path,
      """
      #!/usr/bin/env sh
      printf 'log-to-stderr\\n' >&2
      printf '{"status":"ok"}\\n'
      """
    )

    File.chmod!(script_path, 0o755)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    capture_io(:stderr, fn ->
      assert {~s({"status":"ok"}\n), 0} =
               RanObservability.CommandRunner.System.run(script_path, [], [])
    end)
  end
end
