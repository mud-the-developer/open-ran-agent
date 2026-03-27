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

    assert get_in(status, ["rollback_status", "evidence_ref"]) ==
             "artifacts/replacement/n79_single_ru_single_ue_lab_v1/rollback.json"

    assert get_in(status, ["release_status", "evidence_ref"]) ==
             "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json"

    assert get_in(status, ["conformance_claim", "evidence_tier"]) == "milestone_proof"
    assert get_in(status, ["rollback_status", "evidence_ref"]) =~ "/rollback-evidence.json"
    assert get_in(status, ["release_status", "evidence_ref"]) =~ "/ue-context-release.json"
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

    assert registration_report["summary"] =~ "Downlink NAS Transport"
    assert registration_report["rollback_target"] == "oai_reference"

    assert get_in(registration_report, ["conformance_claim", "evidence_tier"]) ==
             "milestone_proof"

    assert ping_report["summary"] =~ "user-plane failure"
    assert ping_report["rollback_target"] == "oai_reference"

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/registration.json" in ping_report[
             "evidence_refs"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/ping.json" in ping_report[
             "evidence_refs"
           ]

    assert "artifacts/replacement/n79_single_ru_single_ue_lab_v1/attach.json" in registration_report[
             "evidence_refs"
           ]
    assert get_in(ping_report, ["conformance_claim", "evidence_tier"]) == "milestone_proof"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
