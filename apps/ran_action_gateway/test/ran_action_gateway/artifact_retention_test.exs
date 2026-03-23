defmodule RanActionGateway.ArtifactRetentionTest do
  use ExUnit.Case, async: false

  alias RanActionGateway.ArtifactRetention

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-artifact-retention-#{System.unique_integer([:positive, :monotonic])}"
      )

    artifact_root = Path.join(tmp_dir, "artifacts")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(artifact_root)

    create_file(Path.join(artifact_root, "plans/keep.json"), ~D[2026-03-21], ~T[12:00:00])
    create_file(Path.join(artifact_root, "plans/prune.json"), ~D[2026-03-20], ~T[12:00:00])

    create_file(
      Path.join(artifact_root, "control_state/cg-001.json"),
      ~D[2026-03-19],
      ~T[12:00:00]
    )

    create_dir(Path.join(artifact_root, "runtime/runtime-new"), ~D[2026-03-21], ~T[13:00:00])
    create_dir(Path.join(artifact_root, "runtime/runtime-old"), ~D[2026-03-20], ~T[13:00:00])

    create_dir(Path.join(artifact_root, "releases/release-new"), ~D[2026-03-21], ~T[14:00:00])
    create_dir(Path.join(artifact_root, "releases/release-old"), ~D[2026-03-20], ~T[14:00:00])

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{artifact_root: artifact_root}
  end

  test "plan classifies stale artifact entries for pruning", %{artifact_root: artifact_root} do
    plan =
      ArtifactRetention.plan(
        artifact_root: artifact_root,
        json_keep: 1,
        runtime_keep: 1,
        release_keep: 1
      )

    prune_paths = Enum.map(plan.prune, & &1.path)
    protected_paths = Enum.map(plan.protected, & &1.path)

    assert Path.join(artifact_root, "plans/prune.json") in prune_paths
    assert Path.join(artifact_root, "runtime/runtime-old") in prune_paths
    assert Path.join(artifact_root, "releases/release-old") in prune_paths
    assert Path.join(artifact_root, "control_state/cg-001.json") in protected_paths
    assert plan.summary.prune_count == 3
  end

  test "apply removes stale entries but keeps protected control state", %{
    artifact_root: artifact_root
  } do
    assert {:ok, result} =
             ArtifactRetention.apply(
               artifact_root: artifact_root,
               json_keep: 1,
               runtime_keep: 1,
               release_keep: 1
             )

    assert result.status == "pruned"
    refute File.exists?(Path.join(artifact_root, "plans/prune.json"))
    refute File.exists?(Path.join(artifact_root, "runtime/runtime-old"))
    refute File.exists?(Path.join(artifact_root, "releases/release-old"))
    assert File.exists?(Path.join(artifact_root, "control_state/cg-001.json"))
  end

  defp create_file(path, date, time) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "{}")
    File.touch!(path, NaiveDateTime.new!(date, time) |> NaiveDateTime.to_erl())
  end

  defp create_dir(path, date, time) do
    File.mkdir_p!(path)
    marker = Path.join(path, ".keep")
    File.write!(marker, "")
    File.touch!(marker, NaiveDateTime.new!(date, time) |> NaiveDateTime.to_erl())
  end
end
