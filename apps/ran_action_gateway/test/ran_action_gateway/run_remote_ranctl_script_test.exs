defmodule RanActionGateway.RunRemoteRanctlScriptTest do
  use ExUnit.Case, async: false

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-remote-ranctl-script-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  test "blocked remote result marks the failed phase in debug summary", %{tmp_dir: tmp_dir} do
    repo_root = Path.expand("../../../..", __DIR__)
    fake_bin = Path.join(tmp_dir, "bin")
    request_path = Path.join(tmp_dir, "precheck-target-host.json")

    File.mkdir_p!(fake_bin)

    File.write!(
      Path.join(fake_bin, "ssh"),
      """
      #!/usr/bin/env bash
      set -euo pipefail

      case "$*" in
        *"/bin/ranctl"*)
          printf '%s\\n' '{"status":"blocked","change_id":"chg-remote-001","errors":["host readiness is blocked"]}'
          ;;
        *)
          exit 0
          ;;
      esac
      """
    )

    File.write!(
      Path.join(fake_bin, "scp"),
      """
      #!/usr/bin/env bash
      exit 0
      """
    )

    File.chmod!(Path.join(fake_bin, "ssh"), 0o755)
    File.chmod!(Path.join(fake_bin, "scp"), 0o755)

    File.write!(
      request_path,
      JSON.encode!(%{
        "scope" => "target_host",
        "target_ref" => "host-n79-lab-01",
        "target_backend" => "replacement_shadow",
        "current_backend" => "oai_reference",
        "rollback_target" => "oai_reference",
        "change_id" => "chg-remote-001",
        "reason" => "remote precheck",
        "idempotency_key" => "chg-remote-001",
        "ttl" => "20m",
        "verify_window" => %{"duration" => "30s", "checks" => ["host_preflight"]},
        "max_blast_radius" => "single_lab",
        "metadata" => %{
          "replacement" => %{
            "target_role" => "target_host",
            "action" => "precheck",
            "target_profile" => "n79_single_ru_single_ue_lab_v1",
            "core_profile" => "open5gs_nsa_lab_v1",
            "band" => "n79",
            "plane_scope" => ["s_plane", "m_plane", "c_plane", "u_plane"],
            "desired_state" => "present",
            "cutover_mode" => "none",
            "allow_oai_fallback" => true,
            "destructive" => false,
            "real_ru_required" => true,
            "real_ue_required" => true,
            "required_interfaces" => ["ngap", "ru_fronthaul", "ptp"],
            "acceptance_gates" => ["host_preflight", "ru_sync"],
            "open5gs_core" => %{
              "profile" => "open5gs_nsa_lab_v1",
              "n2" => %{"amf_host" => "10.41.83.45", "amf_port" => 38412}
            },
            "native_probe" => %{"strict_host_probe" => true, "required_resources" => ["sync0"]}
          }
        }
      })
    )

    {output, exit_code} =
      File.cd!(tmp_dir, fn ->
        System.cmd(
          "bash",
          [
            Path.join(repo_root, "ops/deploy/run_remote_ranctl.sh"),
            "ran-lab-01",
            "precheck",
            request_path
          ],
          env: [
            {"PATH", "#{fake_bin}:#{System.get_env("PATH")}"},
            {"RAN_REMOTE_APPLY", "1"},
            {"RAN_REMOTE_FETCH", "0"}
          ],
          stderr_to_stdout: true
        )
      end)

    assert exit_code == 1
    assert output =~ "Remote command completed"

    [summary_path] =
      Path.wildcard(
        Path.join([
          tmp_dir,
          "artifacts",
          "remote_runs",
          "ran-lab-01",
          "*-precheck",
          "debug-summary.txt"
        ])
      )

    summary = File.read!(summary_path)

    assert summary =~ "status=blocked"
    assert summary =~ "failed_step=precheck"
    assert summary =~ "exit_code=1"
  end
end
