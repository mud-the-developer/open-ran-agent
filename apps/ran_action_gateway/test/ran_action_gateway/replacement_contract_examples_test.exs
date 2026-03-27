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

    assert "the current target profile does not claim multi-cell or multi-DU parity" in compatibility[
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

  test "repo-visible docs keep runtime support posture explicit" do
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

    assert readme =~ "Runtime lanes with repo-visible proof are explicit and reviewable"
    assert readme =~ "`aerial_clean_room_runtime_v1`"
    assert readme =~ "`cumac_scheduler_clean_room_runtime_v1`"
    assert readme =~ "`YON-60`"
    assert readme =~ "Declared live protocol lane"
    assert overview =~ "evidence-backed runtime lanes"
    assert overview =~ "bounded clean-room `aerial_clean_room_runtime_v1` gateway lane"
    assert contract =~ "bounded clean-room runtime support surface"
    assert contract =~ "`aerial_clean_room_runtime_v1`"
    assert contract =~ "`cumac_scheduler_clean_room_runtime_v1`"
    assert posture =~ "Live-lab validated declared lane"
    assert posture =~ "Bounded clean-room runtime support"
    assert posture =~ "Bounded clean-room scheduler support"
    assert roadmap =~ "Evidence-backed Runtime Lanes"
    assert roadmap =~ "| `Aerial clean-room runtime` |"
    assert roadmap =~ "| `cuMAC clean-room scheduler` |"
    assert roadmap =~ "vendor-backed NVIDIA Aerial integration"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
