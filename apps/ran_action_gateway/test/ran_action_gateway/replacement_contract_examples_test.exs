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

    assert "subprojects/ran_replacement/notes/17-n79-single-ru-open5gs-support-matrix-delta.md" in profile[
             "support_matrix_delta_refs"
           ]

    assert compatibility["compatibility_profile"] == "open5gs_public_surface_ran_visible_v1"
    assert compatibility["required_nf_set"] == ["AMF", "SMF", "UPF"]
    assert "NGAP" in compatibility["required_io_surfaces"]
    assert "GTP-U" in compatibility["required_io_surfaces"]

    assert "the current target profile does not claim multi-cell or multi-DU parity" in compatibility[
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

  test "repo-visible docs keep interoperability roadmap lanes explicit" do
    readme = repo_path("README.md") |> File.read!()
    overview = repo_path("docs/architecture/00-system-overview.md") |> File.read!()

    contract =
      repo_path("docs/architecture/04-du-high-southbound-contract.md")
      |> File.read!()

    roadmap =
      repo_path("docs/architecture/07-mvp-scope-and-roadmap.md")
      |> File.read!()

    interoperability =
      repo_path("docs/architecture/15-production-control-evidence-and-interoperability-lanes.md")
      |> File.read!()

    replacement_readme = repo_path("subprojects/ran_replacement/README.md") |> File.read!()

    assert readme =~ "Future interoperability lanes are explicit and reviewable"
    assert readme =~ "`YON-58`"
    assert readme =~ "`YON-59`"
    assert readme =~ "`YON-60`"
    assert readme =~ "Roadmap-only interoperability lanes"
    assert overview =~ "future interoperability lanes"
    assert overview =~ "roadmap-only set"
    assert contract =~ "not a claim of"
    assert contract =~ "proven external interoperability"
    assert contract =~ "roadmap-only in `YON-58`"
    assert contract =~ "roadmap-only in `YON-59`"
    assert contract =~ "expansion beyond the current bootstrap profile set remains roadmap-only"
    assert contract =~ "`YON-60`"
    assert roadmap =~ "roadmap-only interoperability lanes"
    assert roadmap =~ "| `Aerial interoperability` |"
    assert roadmap =~ "| `cuMAC scheduler interoperability` |"
    assert roadmap =~ "| `broader profile expansion` |"
    assert interoperability =~ "schema-backed family"
    assert interoperability =~ "support-matrix delta"
    assert replacement_readme =~ "schema-backed family bundle"
    assert replacement_readme =~ "family-specific support-matrix delta"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
