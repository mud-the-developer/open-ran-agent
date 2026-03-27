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

    assert Enum.any?(status["checks"], fn check ->
             check["name"] == "rollback_target_known" and check["status"] == "ok"
           end)
  end

  test "replacement compare reports carry explicit summaries" do
    ru_report =
      repo_path(
        "subprojects/ran_replacement/examples/artifacts/compare-report-failed-ru-sync-open5gs-n79.json"
      )
      |> File.read!()
      |> JSON.decode!()

    registration_report =
      repo_path(
        "subprojects/ran_replacement/examples/artifacts/compare-report-registration-rejected-open5gs-n79.json"
      )
      |> File.read!()
      |> JSON.decode!()

    ping_report =
      repo_path(
        "subprojects/ran_replacement/examples/artifacts/compare-report-ping-failed-open5gs-n79.json"
      )
      |> File.read!()
      |> JSON.decode!()

    cutover_report =
      repo_path(
        "subprojects/ran_replacement/examples/artifacts/compare-report-failed-cutover-open5gs-n79.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert ru_report["failure_class"] == "ru_failure"
    assert ru_report["comparison_scope"] == "ru_sync"
    assert ru_report["rollback_target"] == "oai_reference"

    assert registration_report["summary"] =~ "Downlink NAS Transport"
    assert registration_report["rollback_target"] == "oai_reference"

    assert get_in(registration_report, ["conformance_claim", "evidence_tier"]) ==
             "milestone_proof"

    assert ping_report["summary"] =~ "user-plane failure"
    assert ping_report["rollback_target"] == "oai_reference"
    assert get_in(ping_report, ["conformance_claim", "evidence_tier"]) == "milestone_proof"

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json" in ping_report[
             "evidence_refs"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json" in ping_report[
             "evidence_refs"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json" in registration_report[
             "evidence_refs"
           ]

    assert cutover_report["failure_class"] == "cutover_or_rollback_failure"
    assert cutover_report["comparison_scope"] == "cutover"
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
        repo_path("subprojects/ran_replacement/examples/artifacts/#{filename}")
        |> File.read!()
        |> JSON.decode!()

      assert evidence["failure_class"] == failure_class
      assert evidence["rollback_target"] == "oai_reference"

      assert get_in(evidence, ["ngap_subset", "standards_subset_ref"]) =~
               "06-ngap-and-registration-standards-subset.md"
    end)

    post_rollback_verify =
      repo_path(
        "subprojects/ran_replacement/examples/artifacts/post-rollback-verify-gnb-cutover-open5gs-n79.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert post_rollback_verify["restored_from"] == "replacement_primary"
    assert post_rollback_verify["rollback_target"] == "oai_reference"
    assert "post_rollback_verify_recorded" in post_rollback_verify["verification_checks"]
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
