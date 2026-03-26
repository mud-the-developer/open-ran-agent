defmodule RanActionGateway.ReplacementContractExamplesTest do
  use ExUnit.Case, async: true

  test "ngap docs and ranctl examples keep conformance metadata wording explicit" do
    ranctl_readme =
      repo_path("subprojects/ran_replacement/examples/ranctl/README.md")
      |> File.read!()

    gates_note =
      repo_path("subprojects/ran_replacement/notes/12-standards-evidence-and-acceptance-gates.md")
      |> File.read!()

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

    ngap_contract =
      repo_path("subprojects/ran_replacement/packages/ngap_edge/CONTRACT.md")
      |> File.read!()

    assert ranctl_readme =~ "metadata.replacement.ngap_subset"
    assert gates_note =~ "`failure_class`"
    assert gates_note =~ "`ngap_subset`"
    assert runbook =~ "`ngap_subset`"
    assert runbook =~ "`core_failure`"
    assert templates =~ "`failure_class`"
    assert templates =~ "`ngap_subset`"
    assert dashboard =~ "`failure_class`"
    assert ngap_contract =~ "`failure_class`"
    assert ngap_contract =~ "`ngap_subset`"
  end

  defp repo_path(path), do: Path.expand(Path.join(["../../../..", path]), __DIR__)
end
