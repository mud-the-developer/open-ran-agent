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

  @optional_procedure_terms [
    "Error Indication",
    "Reset"
  ]

  @deferred_user_plane_terms [
    "handover",
    "roaming",
    "multi-ue",
    "traffic shaping"
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

  test "repo-visible claim docs separate required, optional, and deferred procedures" do
    support_matrix =
      repo_path("subprojects/ran_replacement/notes/09-ngap-procedure-support-matrix.md")
      |> File.read!()

    status_readme =
      repo_path("subprojects/ran_replacement/examples/status/README.md")
      |> File.read!()

    package_readme =
      repo_path("subprojects/ran_replacement/packages/ngap_edge/README.md")
      |> File.read!()

    contract =
      repo_path("subprojects/ran_replacement/packages/ngap_edge/CONTRACT.md")
      |> File.read!()

    Enum.each(@required_ngap_subset, fn procedure ->
      assert support_matrix =~ "| `#{procedure}` |"
      assert status_readme =~ "- `#{procedure}`"
      assert package_readme =~ "- `#{procedure}`"
      assert contract =~ "- `#{procedure}`"
    end)

    Enum.each(@optional_procedure_terms, fn procedure ->
      assert support_matrix =~ "| `#{procedure}` |"
      assert status_readme =~ "- `#{procedure}`"
      assert package_readme =~ "- `#{procedure}`"
      assert contract =~ "- `#{procedure}`"
    end)

    Enum.each(["Paging", "Handover Preparation", "Path Switch Request"], fn procedure ->
      assert support_matrix =~ "| `#{procedure}` |"
      assert status_readme =~ "- `#{procedure}`"
      assert package_readme =~ "- `#{procedure}`"
      assert contract =~ "- `#{procedure}`"
    end)

    assert status_readme =~ "### Required procedure claims"
    assert status_readme =~ "### Optional recovery claims"
    assert status_readme =~ "### Deferred procedure claims"
    assert package_readme =~ "## Claim Taxonomy"
    assert contract =~ "## Claim Categories"
  end

  test "control-plane cutover examples keep release and rollback evidence explicit" do
    package_status =
      repo_path(
        "subprojects/ran_replacement/packages/f1e1_control_edge/examples/observe-failed-cutover.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    global_status =
      repo_path(
        "subprojects/ran_replacement/examples/status/observe-failed-cutover-open5gs-n79.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    for status <- [package_status, global_status] do
      assert status["rollback_target"] == "oai_reference"
      assert status["rollback_available"] == true
      assert get_in(status, ["rollback_status", "status"]) == "pending"
      assert get_in(status, ["rollback_status", "evidence_ref"]) =~ "/rollback-evidence.json"
      assert get_in(status, ["release_status", "status"]) == "ok"
      assert get_in(status, ["release_status", "evidence_ref"]) =~ "/control-plane-release.json"

      assert Enum.any?(status["checks"], fn check ->
               check["name"] == "control_plane_release_evidence_present" and
                 check["status"] == "ok"
             end)
    end
  end

  test "user-plane verify example keeps tunnel/session vocabulary explicit" do
    status =
      repo_path(
        "subprojects/ran_replacement/examples/status/verify-attach-ping-open5gs-n79.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert get_in(status, ["interface_status", "f1_u", "evidence_ref"]) =~ "/f1-u.json"
    assert get_in(status, ["interface_status", "gtpu", "evidence_ref"]) =~ "/gtpu.json"
    assert get_in(status, ["plane_status", "u_plane", "evidence_ref"]) =~ "/user-plane.json"
    assert get_in(status, ["pdu_session_status", "evidence_ref"]) =~ "/pdu-session.json"
    assert get_in(status, ["ping_status", "evidence_ref"]) =~ "/ping.json"

    assert Enum.any?(status["checks"], fn check ->
             check["name"] == "pdu_session_established" and check["status"] == "ok"
           end)

    assert Enum.any?(status["checks"], fn check ->
             check["name"] == "ping_success" and check["status"] == "ok"
           end)
  end

  test "user-plane docs keep deferred vocabulary out of supported claims" do
    package_readme =
      repo_path("subprojects/ran_replacement/packages/user_plane_edge/README.md")
      |> File.read!()

    contract =
      repo_path("subprojects/ran_replacement/packages/user_plane_edge/CONTRACT.md")
      |> File.read!()

    subset_note =
      repo_path("subprojects/ran_replacement/notes/08-f1-u-and-gtpu-standards-subset.md")
      |> File.read!()

    matrix_note =
      repo_path("subprojects/ran_replacement/notes/11-f1-u-and-gtpu-procedure-support-matrix.md")
      |> File.read!()

    assert package_readme =~ "## Vocabulary Boundaries"
    assert contract =~ "## Vocabulary Rules"
    assert package_readme =~ "- `F1-U` forwarding path"
    assert package_readme =~ "- `GTP-U` tunnel and `TEID` association"
    assert contract =~ "- `F1-U` forwarding state for the declared route"
    assert contract =~ "- `GTP-U` tunnel and `TEID` association for the declared UE session"

    Enum.each(@deferred_user_plane_terms, fn term ->
      assert String.contains?(String.downcase(package_readme), term)
      assert String.contains?(String.downcase(contract), term)
      assert String.contains?(String.downcase(subset_note), term)
      assert String.contains?(String.downcase(matrix_note), term)
    end)
  end

  test "repo-visible docs separate standards-subset claims from compatibility claims" do
    replacement_readme =
      repo_path("subprojects/ran_replacement/README.md")
      |> File.read!()

    notes_readme =
      repo_path("subprojects/ran_replacement/notes/README.md")
      |> File.read!()

    artifacts_readme =
      repo_path("subprojects/ran_replacement/examples/artifacts/README.md")
      |> File.read!()

    ranctl_readme =
      repo_path("subprojects/ran_replacement/examples/ranctl/README.md")
      |> File.read!()

    adr_0006 =
      repo_path("docs/adr/0006-open5gs-public-surface-compatibility-baseline.md")
      |> File.read!()

    adr_0008 =
      repo_path("docs/adr/0008-oai-cu-du-function-and-standards-baseline.md")
      |> File.read!()

    assert replacement_readme =~ "## Claim Separation"
    assert replacement_readme =~ "### Standards-subset claims"
    assert replacement_readme =~ "### Public-surface compatibility claims"
    assert artifacts_readme =~ "## Claim Boundary"
    assert ranctl_readme =~ "Claim boundary:"
    assert notes_readme =~ "## How To Read Claims"
    assert adr_0006 =~ "compatibility baseline"
    assert adr_0008 =~ "standards-correct behavior"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
