defmodule RanActionGateway.ReplacementExamplesTest do
  use ExUnit.Case, async: true

  @required_ngap_subset [
    "NG Setup",
    "Initial UE Message",
    "Uplink NAS Transport",
    "Downlink NAS Transport",
    "UE Context Release"
  ]

  @deferred_procedure_terms [
    "Paging",
    "Handover Required",
    "Path Switch Request",
    "Path Switch Request Acknowledge",
    "UE Context Modification",
    "PDU Session Resource Modify"
  ]

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
    assert get_in(status, ["rollback_status", "evidence_ref"]) =~ "/rollback-evidence.json"
    assert get_in(status, ["release_status", "evidence_ref"]) =~ "/ue-context-release.json"
    assert get_in(status, ["ngap_procedure_trace", "last_observed"]) == "UE Context Release"

    assert get_in(status, ["interface_status", "ngap", "evidence_ref"]) =~
             "artifacts/replacement/capture/"

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
    assert ping_report["summary"] =~ "user-plane failure"
    assert ping_report["rollback_target"] == "oai_reference"
  end

  test "replacement status examples do not imply deferred NGAP procedure support" do
    status_paths = [
      "subprojects/ran_replacement/examples/status/precheck-target-host-open5gs-n79.status.json",
      "subprojects/ran_replacement/examples/status/verify-attach-ping-open5gs-n79.status.json",
      "subprojects/ran_replacement/examples/status/observe-failed-cutover-open5gs-n79.status.json",
      "subprojects/ran_replacement/examples/status/observe-failed-ru-sync-open5gs-n79.status.json",
      "subprojects/ran_replacement/examples/status/capture-artifacts-registration-rejected-open5gs-n79.status.json",
      "subprojects/ran_replacement/examples/status/capture-artifacts-failed-cutover-open5gs-n79.status.json",
      "subprojects/ran_replacement/examples/status/rollback-gnb-cutover-open5gs-n79.status.json",
      "subprojects/ran_replacement/packages/ngap_edge/examples/observe-registration-rejected.status.json"
    ]

    Enum.each(status_paths, fn path ->
      payload = path |> repo_path() |> File.read!() |> JSON.decode!()
      body = JSON.encode!(payload)

      Enum.each(@deferred_procedure_terms, fn term ->
        refute String.contains?(body, term), "#{path} should not imply deferred procedure #{term}"
      end)

      procedure_names =
        get_in(payload, ["ngap_procedure_trace", "procedures"])
        |> List.wrap()
        |> Enum.map(& &1["name"])

      assert procedure_names -- @required_ngap_subset == [],
             "#{path} leaked procedures outside the required subset: #{inspect(procedure_names -- @required_ngap_subset)}"
    end)
  end

  test "ngap standards note keeps deferred procedures explicitly out of scope" do
    note =
      repo_path("subprojects/ran_replacement/notes/06-ngap-and-registration-standards-subset.md")
      |> File.read!()

    assert note =~ "- handover"
    assert note =~ "This subset does not claim:"
    refute note =~ "Path Switch Request"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
