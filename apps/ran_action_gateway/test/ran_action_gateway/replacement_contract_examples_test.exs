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

  test "production-facing hardening docs and rollback schema stay explicit" do
    release_bootstrap =
      repo_path("docs/architecture/10-ci-and-release-bootstrap.md")
      |> File.read!()

    debug_workflow =
      repo_path("docs/architecture/14-debug-and-evidence-workflow.md")
      |> File.read!()

    rollback_schema =
      repo_path("subprojects/ran_replacement/contracts/rollback-evidence-v1.schema.json")
      |> File.read!()
      |> JSON.decode!()

    assert release_bootstrap =~ "## Production-Facing Hardening Boundary"
    assert release_bootstrap =~ "bootstrap-only assumptions"
    assert debug_workflow =~ "## Production-Facing Recovery Bundle"
    assert debug_workflow =~ "operator-facing recovery bundle"

    assert get_in(rollback_schema, ["properties", "support_tier", "enum"]) == [
             "bootstrap",
             "production_hardened",
             "future"
           ]

    assert get_in(rollback_schema, ["properties", "evidence_bundle_class", "enum"]) == [
             "operator_facing_recovery_bundle"
           ]
  end

  test "interoperability roadmap docs keep future lanes explicit" do
    roadmap =
      repo_path("docs/architecture/07-mvp-scope-and-roadmap.md")
      |> File.read!()

    overview =
      repo_path("docs/architecture/00-system-overview.md")
      |> File.read!()

    assert roadmap =~ "roadmap-only interoperability lanes"
    assert roadmap =~ "`Aerial interoperability`"
    assert roadmap =~ "`cuMAC scheduler interoperability`"
    assert roadmap =~ "`broader profile expansion`"
    assert overview =~ "future interoperability lanes"
    assert overview =~ "roadmap-only set"
  end

  test "operator-facing docs keep hardened support claims explicit" do
    docs_index =
      repo_path("docs/index.md")
      |> File.read!()

    debug_workflow =
      repo_path("docs/architecture/14-debug-and-evidence-workflow.md")
      |> File.read!()

    assert docs_index =~ "## Operator-Facing Claim Categories"
    assert docs_index =~ "`bootstrap-only`"
    assert docs_index =~ "`production-hardened`"
    assert docs_index =~ "`future roadmap`"
    assert debug_workflow =~ "support claim explicit"
    assert debug_workflow =~ "`production-hardened`"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
