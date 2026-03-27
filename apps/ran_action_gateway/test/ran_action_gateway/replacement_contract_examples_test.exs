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
    assert posture =~ "Topology-scale claim lanes"
    assert posture =~ "`YON-66`"
    assert roadmap =~ "Evidence-backed Runtime Lanes"
    assert roadmap =~ "`YON-66`"
    assert roadmap =~ "multi-UE"
    assert roadmap =~ "mobility"
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
