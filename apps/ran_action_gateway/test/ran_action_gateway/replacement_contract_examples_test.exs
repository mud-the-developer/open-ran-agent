defmodule RanActionGateway.ReplacementContractExamplesTest do
  use ExUnit.Case, async: true

  test "target profile example names the public-surface compatibility profile" do
    profile =
      repo_path(
        "subprojects/ran_replacement/contracts/examples/n79-single-ru-target-profile-v1.example.json"
      )
      |> File.read!()
      |> JSON.decode!()

    compatibility = profile["compatibility_surface"]

    assert profile["profile_family"] == "n79_single_ru_single_ue_open5gs_family_v1"
    assert profile["ru_family"] == "single_ru_ecpri_ptp_lab_v1"
    assert profile["core_family"] == "open5gs_nsa_lab_v1"

    assert profile["family_bundle_ref"] ==
             "subprojects/ran_replacement/contracts/examples/n79-single-ru-single-ue-open5gs-family-bundle-v1.example.json"

    assert profile["evidence_bundle_root"] ==
             "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/"

    assert get_in(profile, ["standards_subset", "ngap", "bounded_claimed_procedures"]) == [
             "Error Indication",
             "Reset"
           ]

    assert "subprojects/ran_replacement/notes/17-n79-single-ru-open5gs-support-matrix-delta.md" in profile[
             "support_matrix_delta_refs"
           ]

    assert get_in(profile, ["standards_subset", "f1_c", "bounded_claimed_procedures"]) == [
             "UE context modification",
             "Reset-driven recovery"
           ]

    assert get_in(profile, ["standards_subset", "e1ap", "bounded_claimed_procedures"]) == [
             "Bearer context modification"
           ]

    assert get_in(profile, ["standards_subset", "f1_u", "bounded_claimed_procedures"]) == [
             "Tunnel update"
           ]

    assert get_in(profile, ["standards_subset", "gtpu", "bounded_claimed_procedures"]) == [
             "Tunnel rebind"
           ]

    refute Map.has_key?(profile["standards_subset"]["ngap"], "optional_procedures")

    assert compatibility["compatibility_profile"] == "open5gs_public_surface_ran_visible_v1"
    assert compatibility["required_nf_set"] == ["AMF", "SMF", "UPF"]
    assert "NGAP" in compatibility["required_io_surfaces"]
    assert "GTP-U" in compatibility["required_io_surfaces"]

    assert "the current target profile does not claim multi-cell, multi-DU, multi-UE, or mobility parity" in compatibility[
             "declared_deviations"
           ]

    assert "the current target profile does not claim broader RU/core/vendor/profile parity outside n79_single_ru_single_ue_lab_v1" in compatibility[
             "declared_deviations"
           ]

    assert compatibility["evidence_ref"] =~
             "0006-open5gs-public-surface-compatibility-baseline"
  end

  test "current n79 lane is declared through a bounded family bundle" do
    bundle =
      repo_path(
        "subprojects/ran_replacement/contracts/examples/n79-single-ru-single-ue-open5gs-family-bundle-v1.example.json"
      )
      |> File.read!()
      |> JSON.decode!()

    compare_reports = get_in(bundle, ["evidence_bundle", "compare_reports"])
    rollback_evidence = get_in(bundle, ["evidence_bundle", "rollback_evidence"])

    assert bundle["family_id"] == "n79_single_ru_single_ue_open5gs_family_v1"
    assert get_in(bundle, ["target_profile", "profile"]) == "n79_single_ru_single_ue_lab_v1"
    assert get_in(bundle, ["ru_family", "name"]) == "single_ru_ecpri_ptp_lab_v1"
    assert get_in(bundle, ["core_family", "profile"]) == "open5gs_nsa_lab_v1"

    assert get_in(bundle, ["core_family", "example_ref"]) ==
             "subprojects/ran_replacement/contracts/examples/open5gs-core-link-profile-v1.example.json"

    assert get_in(bundle, ["evidence_bundle", "artifact_root"]) ==
             "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/"

    assert "subprojects/ran_replacement/notes/17-n79-single-ru-open5gs-support-matrix-delta.md" in bundle[
             "support_matrix_delta_refs"
           ]

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/compare-report-failed-ru-sync-open5gs-n79.json" in compare_reports

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/compare-report-registration-rejected-open5gs-n79.json" in compare_reports

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/compare-report-ping-failed-open5gs-n79.json" in compare_reports

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/compare-report-failed-cutover-open5gs-n79.json" in compare_reports

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/rollback-evidence-failed-ru-sync-open5gs-n79.json" in rollback_evidence

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/rollback-evidence-registration-rejected-open5gs-n79.json" in rollback_evidence

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/rollback-evidence-ping-failed-open5gs-n79.json" in rollback_evidence

    assert "subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/rollback-evidence-failed-cutover-open5gs-n79.json" in rollback_evidence
  end

  test "lab-owner overlay example names operator-facing compatibility alignment" do
    overlay =
      repo_path(
        "subprojects/ran_replacement/contracts/examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json"
      )
      |> File.read!()
      |> JSON.decode!()

    compatibility = overlay["compatibility_alignment"]

    assert compatibility["compatibility_profile"] == "open5gs_public_surface_ran_visible_v1"
    assert compatibility["required_nf_set"] == ["AMF", "SMF", "UPF"]
    assert "metrics" in compatibility["required_io_surfaces"]
    assert "remote-run summary" in compatibility["operator_surfaces"]
  end

  test "repo-visible docs keep runtime support posture and topology decomposition explicit" do
    readme = repo_path("README.md") |> File.read!()
    overview = repo_path("docs/architecture/00-system-overview.md") |> File.read!()

    posture =
      repo_path("docs/architecture/15-production-control-evidence-and-interoperability-lanes.md")
      |> File.read!()

    contract =
      repo_path("docs/architecture/04-du-high-southbound-contract.md")
      |> File.read!()

    roadmap =
      repo_path("docs/architecture/07-mvp-scope-and-roadmap.md")
      |> File.read!()

    replacement_readme = repo_path("subprojects/ran_replacement/README.md") |> File.read!()

    topology_note =
      repo_path("subprojects/ran_replacement/notes/17-topology-scale-claim-lanes.md")
      |> File.read!()

    assert readme =~ "Runtime lanes with repo-visible proof are explicit and reviewable"
    assert readme =~ "`aerial_clean_room_runtime_v1`"
    assert readme =~ "`cumac_scheduler_clean_room_runtime_v1`"
    assert readme =~ "`YON-66`"
    assert readme =~ "Declared live protocol lane"
    assert readme =~ "Roadmap-only interoperability lanes"
    assert overview =~ "evidence-backed runtime lanes"
    assert overview =~ "`YON-66`"
    assert contract =~ "bounded clean-room runtime support surface"
    assert contract =~ "`aerial_clean_room_runtime_v1`"
    assert contract =~ "`cumac_scheduler_clean_room_runtime_v1`"
    assert contract =~ "`YON-66`"
    assert posture =~ "Live-lab validated declared lane"
    assert posture =~ "Bounded clean-room runtime support"
    assert posture =~ "Bounded clean-room scheduler support"
    assert posture =~ "schema-backed family bundle"
    assert posture =~ "support-matrix delta"
    assert posture =~ "Topology-scale claim lanes"
    assert posture =~ "YON-66"
    assert roadmap =~ "Evidence-backed Runtime Lanes"
    assert roadmap =~ "| `Aerial clean-room runtime` |"
    assert roadmap =~ "| `cuMAC clean-room scheduler` |"
    assert roadmap =~ "vendor-backed NVIDIA Aerial integration"
    assert roadmap =~ "YON-66"
    assert roadmap =~ "multi-UE"
    assert roadmap =~ "mobility"
    assert replacement_readme =~ "schema-backed family bundle"
    assert replacement_readme =~ "YON-66"
    assert topology_note =~ "`YON-60`"
    assert topology_note =~ "`YON-66`"
    assert topology_note =~ "profile-defined and testable"
  end

  test "topology-scope examples define bounded future lanes" do
    multi_cell =
      read_json(
        "subprojects/ran_replacement/contracts/examples/topology-scope-multi-cell-v1.example.json"
      )

    multi_du =
      read_json(
        "subprojects/ran_replacement/contracts/examples/topology-scope-multi-du-v1.example.json"
      )

    multi_ue =
      read_json(
        "subprojects/ran_replacement/contracts/examples/topology-scope-multi-ue-v1.example.json"
      )

    mobility =
      read_json(
        "subprojects/ran_replacement/contracts/examples/topology-scope-mobility-v1.example.json"
      )

    assert multi_cell["scope_class"] == "multi_cell"
    assert multi_cell["topology"]["cell_count"] == 2
    assert multi_cell["status"] == "profile_defined_not_runtime_proven"

    assert multi_du["scope_class"] == "multi_du"
    assert multi_du["topology"]["du_count"] == 2

    assert multi_ue["scope_class"] == "multi_ue"
    assert multi_ue["topology"]["ue_count"] == 4

    assert mobility["scope_class"] == "mobility"
    assert mobility["topology"]["mobility_required"] == true
    assert "no broad topology parity claim outside the declared profile" in mobility["non_claims"]
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)

  defp read_json(path) do
    path
    |> repo_path()
    |> File.read!()
    |> JSON.decode!()
  end
end
