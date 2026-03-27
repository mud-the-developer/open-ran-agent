defmodule RanActionGateway.DeployWizardTest do
  use ExUnit.Case, async: false

  alias RanActionGateway.DeployWizard

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-deploy-wizard-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  test "run with defaults and skip-install writes target-host files", %{tmp_dir: tmp_dir} do
    install_root = Path.join(tmp_dir, "install")
    etc_root = Path.join(tmp_dir, "etc")
    current_root = Path.join(install_root, "current")
    File.mkdir_p!(current_root)

    assert {:ok, result} =
             DeployWizard.run([
               "--defaults",
               "--skip-install",
               "--install-root",
               install_root,
               "--etc-root",
               etc_root,
               "--current-root",
               current_root
             ])

    assert result.status == "configured"
    assert result.install_performed == false
    assert File.exists?(result.files.topology_path)
    assert File.exists?(result.files.request_path)
    assert File.exists?(result.files.dashboard_env_path)
    assert File.exists?(result.files.preflight_env_path)
    assert File.exists?(result.files.profile_path)
    assert File.exists?(result.files.effective_config_path)
    assert File.exists?(result.files.readiness_path)

    assert {:ok, topology} = File.read(result.files.topology_path)
    assert {:ok, topology_payload} = JSON.decode(topology)

    assert get_in(topology_payload, ["cell_groups", Access.at(0), "backend"]) ==
             "local_fapi_profile"

    assert {:ok, request} = File.read(result.files.request_path)
    assert {:ok, request_payload} = JSON.decode(request)

    assert get_in(request_payload, [
             "metadata",
             "deploy_profile",
             "name"
           ]) == "stable_ops"

    assert get_in(request_payload, [
             "metadata",
             "native_probe",
             "session_payload",
             "strict_host_probe"
           ]) ==
             true

    assert {:ok, profile_body} = File.read(result.files.profile_path)
    assert {:ok, profile_payload} = JSON.decode(profile_body)
    assert profile_payload["name"] == "stable_ops"
    assert profile_payload["stability_tier"] == "conservative"
    assert "remote_fetchback" in profile_payload["overlays"]

    assert {:ok, effective_body} = File.read(result.files.effective_config_path)
    assert {:ok, effective_payload} = JSON.decode(effective_body)
    assert effective_payload["deploy_profile"]["name"] == "stable_ops"
    assert effective_payload["dashboard_env"]["RAN_DEPLOY_PROFILE"] == "stable_ops"
    assert effective_payload["paths"]["readiness_path"] == result.files.readiness_path

    assert {:ok, readiness_body} = File.read(result.files.readiness_path)
    assert {:ok, readiness_payload} = JSON.decode(readiness_body)
    assert readiness_payload["status"] == "preview_ready"
    assert readiness_payload["recommendation"] == "package_bundle"
    assert readiness_payload["score"] >= 40
    assert Enum.any?(readiness_payload["checklist"], &(&1["id"] == "target_host"))

    assert File.read!(result.files.dashboard_env_path) =~ "RAN_DASHBOARD_PORT=4050"
    assert File.read!(result.files.dashboard_env_path) =~ "RAN_DEPLOY_PROFILE=stable_ops"
    assert File.read!(result.files.preflight_env_path) =~ "RAN_REPO_ROOT=#{current_root}"
    assert result.handoff.enabled == false
  end

  test "run with remote target produces handoff commands", %{tmp_dir: tmp_dir} do
    bundle_dir = Path.join(tmp_dir, "bundle")
    bundle_tarball = Path.join(bundle_dir, "open_ran_agent-demo.tar.gz")
    installer_path = Path.join(bundle_dir, "install_bundle.sh")

    File.mkdir_p!(bundle_dir)
    File.write!(bundle_tarball, "demo")
    File.write!(installer_path, "#!/usr/bin/env bash\n")

    File.cd!(tmp_dir, fn ->
      assert {:ok, result} =
               DeployWizard.run([
                 "--json",
                 "--defaults",
                 "--safe-preview",
                 "--skip-install",
                 "--bundle",
                 bundle_tarball,
                 "--target-host",
                 "ran-lab-01",
                 "--ssh-user",
                 "ranops",
                 "--ssh-port",
                 "2222"
               ])

      assert result.handoff.enabled == true
      assert result.handoff.ssh_target == "ranops@ran-lab-01"
      assert result.handoff.remote_ranctl_commands != []
      assert result.handoff.fetch_commands != []
      assert result.files.profile_path =~ "deploy.profile.json"
      assert result.files.effective_config_path =~ "deploy.effective.json"
      assert result.files.readiness_path =~ "deploy.readiness.json"
      assert result.readiness.status == "ready_for_preflight"
      assert result.readiness.recommendation == "run_preflight"

      assert result.handoff.remote_bundle_tarball ==
               "/tmp/open-ran-agent/open_ran_agent-demo.tar.gz"

      assert result.etc_root =~ "artifacts/deploy_preview/etc"
      assert result.current_root == tmp_dir

      assert Enum.any?(
               result.handoff.commands,
               &String.contains?(&1, "scp -P '2222'")
             )

      assert Enum.any?(
               result.handoff.commands,
               &String.contains?(&1, "topology.single_du.target_host.rfsim.json")
             )

      assert Enum.any?(
               result.handoff.commands,
               &String.contains?(&1, "ran-host-preflight")
             )

      assert Enum.any?(
               result.handoff.commands,
               &String.contains?(&1, "deploy.profile.json")
             )

      assert Enum.any?(
               result.handoff.commands,
               &String.contains?(&1, "deploy.effective.json")
             )

      assert Enum.any?(
               result.handoff.commands,
               &String.contains?(&1, "deploy.readiness.json")
             )

      assert Enum.any?(
               result.handoff.remote_ranctl_commands,
               &String.contains?(&1, "bin/ran-remote-ranctl")
             )

      assert Enum.map(result.handoff.remote_ranctl_commands, fn command ->
               Enum.find(
                 ["precheck", "plan", "apply", "verify", "capture-artifacts", "rollback"],
                 &String.contains?(command, " #{&1} ")
               )
             end) == [
               "precheck",
               "plan",
               "apply",
               "verify",
               "capture-artifacts",
               "rollback"
             ]

      assert Enum.any?(
               result.handoff.remote_ranctl_commands,
               &String.contains?(&1, "precheck-target-host.json")
             )

      assert Enum.any?(
               result.handoff.remote_ranctl_commands,
               &String.contains?(&1, "plan-gnb-bringup.json")
             )

      assert Enum.any?(
               result.handoff.remote_ranctl_commands,
               &String.contains?(&1, "verify-attach-ping.json")
             )

      assert Enum.any?(
               result.handoff.remote_ranctl_commands,
               &String.contains?(&1, "rollback-gnb-cutover.json")
             )

      assert Enum.any?(
               result.handoff.fetch_commands,
               &String.contains?(&1, "bin/ran-fetch-remote-artifacts")
             )
    end)
  end

  test "run_precheck captures actionable preflight failure detail", %{tmp_dir: tmp_dir} do
    bundle_dir = Path.join(tmp_dir, "bundle")
    bundle_tarball = Path.join(bundle_dir, "open_ran_agent-demo.tar.gz")
    installer_path = Path.join(bundle_dir, "install_bundle.sh")
    current_root = Path.join(tmp_dir, "current")
    preflight_path = Path.join(current_root, "bin/ran-host-preflight")

    File.mkdir_p!(bundle_dir)
    File.write!(bundle_tarball, "demo")
    File.write!(installer_path, "#!/usr/bin/env bash\n")
    File.mkdir_p!(Path.dirname(preflight_path))

    File.write!(
      preflight_path,
      """
      #!/usr/bin/env sh
      echo "missing host interface sync0"
      echo '{"status":"failed","checks":[{"name":"host_preflight","status":"failed"}],"evidence_ref":"artifacts/remote_runs/ran-lab-01/precheck/debug-summary.txt"}'
      exit 1
      """
    )

    File.chmod!(preflight_path, 0o755)

    File.cd!(tmp_dir, fn ->
      assert {:ok, result} =
               DeployWizard.run([
                 "--json",
                 "--defaults",
                 "--safe-preview",
                 "--skip-install",
                 "--bundle",
                 bundle_tarball,
                 "--current-root",
                 current_root,
                 "--target-host",
                 "ran-lab-01",
                 "--ssh-user",
                 "ranops",
                 "--run-precheck"
               ])

      assert result.preflight.status == "failed"
      assert result.preflight.exit_code == 1
      assert result.preflight.response["status"] == "failed"

      assert result.preflight.response["evidence_ref"] ==
               "artifacts/remote_runs/ran-lab-01/precheck/debug-summary.txt"

      assert result.readiness.status == "blocked"
      assert result.readiness.recommendation == "fix_blockers"

      assert Enum.any?(result.readiness.blockers, fn blocker ->
               blocker.id == "preflight" and
                 blocker.detail == "Host preflight failed: missing host interface sync0"
             end)

      assert "Preflight reported failures; inspect the captured output before applying changes." in result.next_steps
    end)
  end
end
