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

  test "repo-visible docs keep interoperability roadmap lanes explicit" do
    readme = repo_path("README.md") |> File.read!()
    overview = repo_path("docs/architecture/00-system-overview.md") |> File.read!()

    contract =
      repo_path("docs/architecture/04-du-high-southbound-contract.md")
      |> File.read!()

    roadmap =
      repo_path("docs/architecture/07-mvp-scope-and-roadmap.md")
      |> File.read!()

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
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
