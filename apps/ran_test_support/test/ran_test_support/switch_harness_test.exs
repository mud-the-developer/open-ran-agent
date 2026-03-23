defmodule RanTestSupport.SwitchHarnessTest do
  use ExUnit.Case, async: false

  alias RanActionGateway.ControlState
  alias RanTestSupport.SwitchHarness

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-switch-harness-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    ControlState.reset()

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  test "switch harness drives successful controlled rollback path", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      payload = base_payload()

      assert {:ok, %{results: results}} =
               SwitchHarness.run_sequence(payload, [:precheck, :plan, :apply, :verify, :rollback])

      assert results.precheck.status == "ok"
      assert results.plan.status == "planned"
      assert results.plan.rollback_target == "stub_fapi_profile"
      assert results.apply.status == "applied"
      assert results.verify.status == "verified"
      assert results.rollback.status == "rolled_back"

      refs = SwitchHarness.artifact_refs(payload["change_id"])

      assert File.exists?(refs.plan)
      assert File.exists?(refs.change_state)
      assert File.exists?(refs.verify)
      assert File.exists?(refs.rollback_plan)
      assert File.exists?(refs.apply_approval)
      assert File.exists?(refs.rollback_approval)
    end)
  end

  test "switch harness supports failed verify followed by capture and rollback", %{
    tmp_dir: tmp_dir
  } do
    File.cd!(tmp_dir, fn ->
      payload =
        base_payload(%{
          "incident_id" => "inc-switch-harness-001",
          "metadata" => %{"simulate_failure" => true}
        })

      assert {:ok, %{results: results}} =
               SwitchHarness.run_sequence(payload, [
                 :plan,
                 :apply,
                 :verify,
                 :capture_artifacts,
                 :rollback
               ])

      assert results.verify.status == "failed"
      assert results.capture_artifacts.status == "captured"
      assert results.rollback.status == "rolled_back"

      refs = SwitchHarness.artifact_refs(payload["change_id"], payload["incident_id"])
      assert File.exists?(refs.capture)
    end)
  end

  defp base_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "scope" => "cell_group",
        "cell_group" => "cg-001",
        "target_backend" => "local_fapi_profile",
        "current_backend" => "stub_fapi_profile",
        "change_id" => "chg-harness-001",
        "reason" => "exercise switch harness",
        "idempotency_key" => "chg-harness-001-key",
        "dry_run" => false,
        "ttl" => "15m",
        "verify_window" => %{"duration" => "30s", "checks" => ["gateway_healthy"]},
        "max_blast_radius" => "single_cell_group",
        "approval" => %{
          "approved" => true,
          "approved_by" => "switch.harness",
          "approved_at" => "2026-03-21T00:00:00Z",
          "ticket_ref" => "CHG-HARNESS-001",
          "source" => "integration-test",
          "evidence" => ["docs/architecture/05-ranctl-action-model.md"]
        }
      },
      overrides
    )
  end
end
