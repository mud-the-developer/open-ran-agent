defmodule RanActionGateway.ReplacementExamplesTest do
  use ExUnit.Case, async: true

  test "failed-cutover capture example uses rollback-review vocabulary" do
    status =
      repo_path(
        "subprojects/ran_replacement/examples/status/capture-artifacts-failed-cutover-open5gs-n79.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert status["summary"] =~ "failed replacement evidence bundle"
    assert status["gate_class"] == "blocked"
    assert status["rollback_target"] == "oai_reference"
    assert status["rollback_available"] == true
    assert get_in(status, ["conformance_claim", "evidence_tier"]) == "milestone_proof"

    assert get_in(status, ["rollback_status", "evidence_ref"]) ==
             "artifacts/replacement/n79_single_ru_single_ue_lab_v1/rollback.json"

    assert get_in(status, ["release_status", "evidence_ref"]) ==
             "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

    assert get_in(status, ["ngap_procedure_trace", "last_observed"]) == "UE Context Release"

    assert Map.new(status["ngap_procedure_trace"]["procedures"], &{&1["name"], &1["status"]})[
             "Reset"
           ] == "pending"

    assert get_in(status, ["interface_status", "ngap", "evidence_ref"]) ==
             "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json" in status[
             "artifacts"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json" in status[
             "artifacts"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/pdu-session.json" in status[
             "artifacts"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json" in status["artifacts"]

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/ngap-reset-failed-cutover-open5gs-n79.json" in status[
             "artifacts"
           ]

    assert Enum.any?(status["checks"], fn check ->
             check["name"] == "rollback_target_known" and check["status"] == "ok"
           end)
  end

  test "replacement compare reports carry explicit summaries" do
    ru_report =
      family_artifact("compare-report-failed-ru-sync-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    registration_report =
      family_artifact("compare-report-registration-rejected-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    ping_report =
      family_artifact("compare-report-ping-failed-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    cutover_report =
      family_artifact("compare-report-failed-cutover-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    assert ru_report["failure_class"] == "ru_failure"
    assert ru_report["comparison_scope"] == "ru_sync"
    assert ru_report["rollback_target"] == "oai_reference"

    assert registration_report["summary"] =~ "Downlink NAS Transport"
    assert registration_report["rollback_target"] == "oai_reference"

    assert get_in(registration_report, ["conformance_claim", "evidence_tier"]) ==
             "milestone_proof"

    assert ping_report["summary"] =~ "stale tunnel cleanup"
    assert ping_report["rollback_target"] == "oai_reference"
    assert get_in(ping_report, ["conformance_claim", "evidence_tier"]) == "milestone_proof"

    assert get_in(ping_report, ["expected_state", "stale_tunnel_cleanup"]) =~
             "explicitly cleaned before another session attempt"

    assert get_in(ping_report, ["observed_state", "session_scope"]) =~
             "same-UE next-session safety"

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json" in ping_report[
             "evidence_refs"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json" in ping_report[
             "evidence_refs"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json" in registration_report[
             "evidence_refs"
           ]

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/ngap-error-indication-registration-rejected-open5gs-n79.json" in registration_report[
             "evidence_refs"
           ]

    assert cutover_report["failure_class"] == "cutover_or_rollback_failure"
    assert cutover_report["comparison_scope"] == "cutover"

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/ngap-reset-failed-cutover-open5gs-n79.json" in cutover_report[
             "evidence_refs"
           ]
  end

  test "published status fixtures cover each declared replay lane" do
    fixtures = [
      {"observe-failed-ru-sync-open5gs-n79.status.json", "ru_failure"},
      {"capture-artifacts-failed-ru-sync-open5gs-n79.status.json", "ru_failure"},
      {"observe-registration-rejected-open5gs-n79.status.json", "core_failure"},
      {"capture-artifacts-registration-rejected-open5gs-n79.status.json", "core_failure"},
      {"observe-ping-failed-open5gs-n79.status.json", "user_plane_failure"},
      {"capture-artifacts-ping-failed-open5gs-n79.status.json", "user_plane_failure"},
      {"observe-failed-cutover-open5gs-n79.status.json", "cutover_or_rollback_failure"},
      {"capture-artifacts-failed-cutover-open5gs-n79.status.json", "cutover_or_rollback_failure"},
      {"rollback-gnb-cutover-open5gs-n79.status.json", "cutover_or_rollback_failure"}
    ]

    Enum.each(fixtures, fn {filename, failure_class} ->
      status =
        repo_path("subprojects/ran_replacement/examples/status/#{filename}")
        |> File.read!()
        |> JSON.decode!()

      assert status["failure_class"] == failure_class
      assert status["rollback_target"] == "oai_reference"

      assert get_in(status, ["ngap_subset", "standards_subset_ref"]) =~
               "06-ngap-and-registration-standards-subset.md"
    end)

    ping_observe =
      repo_path(
        "subprojects/ran_replacement/examples/status/observe-ping-failed-open5gs-n79.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert ping_observe["summary"] =~ "stale tunnel cleanup remains under review"
    assert get_in(ping_observe, ["interface_status", "f1_u", "reason"]) =~ "stale forwarding"
    assert get_in(ping_observe, ["interface_status", "gtpu", "reason"]) =~ "stale TEID cleanup"
    assert get_in(ping_observe, ["rollback_status", "reason"]) =~ "stale tunnel cleanup"

    rollback_status =
      repo_path(
        "subprojects/ran_replacement/examples/status/rollback-gnb-cutover-open5gs-n79.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert rollback_status["summary"] =~ "stale tunnel cleanup"

    assert Enum.any?(rollback_status["checks"], fn check ->
             check["name"] == "stale_tunnel_cleanup_confirmed" and check["status"] == "ok"
           end)
  end

  test "rollback evidence fixtures preserve replay and restore context" do
    fixtures = [
      {"rollback-evidence-failed-ru-sync-open5gs-n79.json", "ru_failure"},
      {"rollback-evidence-registration-rejected-open5gs-n79.json", "core_failure"},
      {"rollback-evidence-ping-failed-open5gs-n79.json", "user_plane_failure"},
      {"rollback-evidence-failed-cutover-open5gs-n79.json", "cutover_or_rollback_failure"}
    ]

    Enum.each(fixtures, fn {filename, failure_class} ->
      evidence =
        family_artifact(filename)
        |> File.read!()
        |> JSON.decode!()

      assert evidence["failure_class"] == failure_class
      assert evidence["rollback_target"] == "oai_reference"

      assert get_in(evidence, ["ngap_subset", "standards_subset_ref"]) =~
               "06-ngap-and-registration-standards-subset.md"
    end)

    ping_evidence =
      family_artifact("rollback-evidence-ping-failed-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    assert get_in(ping_evidence, ["pre_rollback_state", "stale_tunnel_cleanup"]) =~
             "cleanup evidence before another session attempt"

    assert get_in(ping_evidence, ["post_rollback_state", "session_scope"]) =~
             "does not claim broader multi-session parity"

    assert "stale_tunnel_cleanup_reviewable" in get_in(ping_evidence, ["recovery_check", "checks"])

    assert "single_session_scope_explicit" in get_in(ping_evidence, ["recovery_check", "checks"])

    post_rollback_verify =
      family_artifact("post-rollback-verify-gnb-cutover-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    assert post_rollback_verify["restored_from"] == "replacement_primary"
    assert post_rollback_verify["rollback_target"] == "oai_reference"
    assert "post_rollback_verify_recorded" in post_rollback_verify["verification_checks"]
    assert "stale_tunnel_cleanup_confirmed" in post_rollback_verify["verification_checks"]
    assert get_in(post_rollback_verify, ["restored_state", "summary"]) =~ "stale tunnel cleanup"

    assert get_in(post_rollback_verify, ["restored_state", "session_scope"]) =~
             "does not claim broader multi-session parity"

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/ngap-reset-failed-cutover-open5gs-n79.json" in post_rollback_verify[
             "evidence_refs"
           ]
  end

  test "failed-cutover capture example preserves the bounded family bundle paths" do
    status =
      repo_path(
        "subprojects/ran_replacement/examples/status/capture-artifacts-failed-cutover-open5gs-n79.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/compare-report-registration-rejected-open5gs-n79.json" in status[
             "artifacts"
           ]

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/compare-report-ping-failed-open5gs-n79.json" in status[
             "artifacts"
           ]

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/rollback-evidence-failed-cutover-open5gs-n79.json" in status[
             "artifacts"
           ]

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/ngap-reset-failed-cutover-open5gs-n79.json" in status[
             "artifacts"
           ]
  end

  test "bounded NGAP proof artifacts stay explicit and non-broad" do
    error_indication =
      family_artifact("ngap-error-indication-registration-rejected-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    reset =
      family_artifact("ngap-reset-failed-cutover-open5gs-n79.json")
      |> File.read!()
      |> JSON.decode!()

    assert error_indication["procedure"] == "Error Indication"
    assert error_indication["claim_scope"] == "bounded_recovery_claim"
    assert Enum.join(error_indication["non_claims"], " ") =~ "broad NGAP failure-handling parity"

    assert reset["procedure"] == "Reset"
    assert reset["claim_scope"] == "bounded_recovery_claim"
    assert reset["rollback_target"] == "oai_reference"
    assert Enum.join(reset["non_claims"], " ") =~ "outside the bounded cutover rollback lane"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)

  defp family_artifact(filename) do
    repo_path(
      "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/#{filename}"
    )
  end
end
