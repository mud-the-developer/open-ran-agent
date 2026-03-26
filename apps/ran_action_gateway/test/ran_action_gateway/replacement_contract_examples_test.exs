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

  test "live-lab operator-facing evidence docs define an acceptance dossier" do
    runbook =
      repo_path("subprojects/ran_replacement/notes/13-milestone-1-acceptance-runbook.md")
      |> File.read!()

    templates =
      repo_path(
        "subprojects/ran_replacement/notes/14-compare-report-and-rollback-evidence-templates.md"
      )
      |> File.read!()

    dashboard =
      repo_path("subprojects/ran_replacement/notes/15-dashboard-fixture-mapping.md")
      |> File.read!()

    incidents =
      repo_path("subprojects/ran_replacement/examples/incidents/README.md")
      |> File.read!()

    assert runbook =~ "## Live-Lab Acceptance Dossier"
    assert runbook =~ "operator-facing acceptance dossier"
    assert templates =~ "## Operator-Facing Evidence Bundle"
    assert templates =~ "acceptance summary"
    assert dashboard =~ "combined live-lab acceptance dossier"
    assert incidents =~ "operator-facing"
    assert incidents =~ "acceptance dossier"
  end

  test "dashboard mapping keeps claim categories explicit for mission cards and summaries" do
    dashboard =
      repo_path("subprojects/ran_replacement/notes/15-dashboard-fixture-mapping.md")
      |> File.read!()

    overlay =
      repo_path(
        "subprojects/ran_replacement/contracts/examples/n79-single-ru-target-profile-v1.lab-owner-overlay.example.json"
      )
      |> File.read!()
      |> JSON.decode!()

    operator_surfaces = get_in(overlay, ["compatibility_alignment", "operator_surfaces"])

    assert dashboard =~ "Every mission card should also declare its claim category"
    assert dashboard =~ "- `standards-subset`"
    assert dashboard =~ "- `compatibility-baseline`"
    assert dashboard =~ "- `live-lab acceptance dossier`"
    assert dashboard =~ "mission cards and remote-run summaries should show the claim category"
    assert "dashboard mission cards" in operator_surfaces
    assert "remote-run summary" in operator_surfaces
    assert "rollback evidence bundle" in operator_surfaces
  end

  test "target-host workflow docs keep first-failure and rollback review explicit" do
    readiness_note =
      repo_path("subprojects/ran_replacement/notes/03-target-host-readiness-and-lab-gates.md")
      |> File.read!()

    package_readme =
      repo_path("subprojects/ran_replacement/packages/target_host_edge/README.md")
      |> File.read!()

    contract =
      repo_path("subprojects/ran_replacement/packages/target_host_edge/CONTRACT.md")
      |> File.read!()

    ranctl_readme =
      repo_path("subprojects/ran_replacement/examples/ranctl/README.md")
      |> File.read!()

    fixture =
      repo_path(
        "subprojects/ran_replacement/packages/target_host_edge/examples/precheck-target-host.status.json"
      )
      |> File.read!()
      |> JSON.decode!()

    assert readiness_note =~ "## Operator Workflow Validation"
    assert package_readme =~ "## Operator Validation Boundary"
    assert contract =~ "## Operator Workflow Rules"
    assert ranctl_readme =~ "Operator workflow rule:"
    assert fixture["rollback_target"] == "oai_reference"
    assert fixture["gate_class"] == "blocked"
    assert Enum.at(fixture["checks"], 0)["name"] == "host_preflight"
    assert List.first(fixture["suggested_next"]) =~ "inspect host timing"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
