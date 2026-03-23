defmodule RanActionGateway.ReleaseBundleTest do
  use ExUnit.Case, async: false

  alias RanActionGateway.ReleaseBundle

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-release-bundle-#{System.unique_integer([:positive, :monotonic])}"
      )

    repo_root = Path.join(tmp_dir, "repo")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(repo_root)

    write_fixture(repo_root, "README.md", "# fixture\n")
    write_fixture(repo_root, "AGENTS.md", "# agents\n")
    write_fixture(repo_root, "CODEX_RAN_BOOTSTRAP.md", "# bootstrap\n")
    write_fixture(repo_root, "mix.exs", "defmodule Fixture do\nend\n")
    write_fixture(repo_root, "bin/ran-debug-latest", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ran-install", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ranctl", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ran-dashboard", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ran-deploy-wizard", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ran-fetch-remote-artifacts", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ran-host-preflight", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ran-remote-ranctl", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "bin/ran-ship-bundle", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "apps/ran_core/lib/ran_core.ex", "defmodule RanCore do\nend\n")
    write_fixture(repo_root, "config/config.exs", "import Config\n")

    write_fixture(
      repo_root,
      "config/prod/topology.single_du.target_host.rfsim.json.example",
      "{}\n"
    )

    write_fixture(repo_root, "docs/architecture/00-system-overview.md", "# overview\n")
    write_fixture(repo_root, "examples/ranctl/apply-switch-local.json", "{}\n")
    write_fixture(repo_root, "examples/ranctl/precheck-target-host.json.example", "{}\n")
    write_fixture(repo_root, "native/fapi_rt_gateway/PORT_PROTOCOL.md", "# port\n")
    write_fixture(repo_root, "ops/skills/ran-observe/SKILL.md", "# skill\n")
    write_fixture(repo_root, "ops/deploy/debug_latest.sh", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "ops/deploy/fetch_remote_artifacts.sh", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "ops/deploy/easy_install.sh", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "ops/deploy/install_bundle.sh", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "ops/deploy/run_remote_ranctl.sh", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "ops/deploy/ship_bundle.sh", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "ops/deploy/preflight.sh", "#!/usr/bin/env sh\n")
    write_fixture(repo_root, "ops/deploy/systemd/ran-dashboard.service", "[Unit]\n")
    write_fixture(repo_root, ".github/workflows/ci.yml", "name: ci\n")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{repo_root: repo_root}
  end

  test "build writes manifest and bootstrap tarball", %{repo_root: repo_root} do
    assert {:ok, result} =
             ReleaseBundle.build(
               repo_root: repo_root,
               output_root: Path.join(repo_root, "artifacts/releases"),
               bundle_id: "bootstrap-test"
             )

    assert result.status == "packaged"
    assert File.exists?(result.manifest_path)
    assert File.exists?(result.tarball_path)

    assert {:ok, manifest_body} = File.read(result.manifest_path)
    assert {:ok, manifest} = JSON.decode(manifest_body)
    assert manifest["bundle_id"] == "bootstrap-test"
    assert manifest["release_unit"] == "bootstrap_source_bundle"
    assert "bin/ran-debug-latest" in manifest["entrypoints"]
    assert "bin/ran-install" in manifest["entrypoints"]
    assert "bin/ran-deploy-wizard" in manifest["entrypoints"]
    assert "bin/ran-fetch-remote-artifacts" in manifest["entrypoints"]
    assert "bin/ran-host-preflight" in manifest["entrypoints"]
    assert "bin/ran-remote-ranctl" in manifest["entrypoints"]
    assert "bin/ran-ship-bundle" in manifest["entrypoints"]
    assert "ops/deploy/debug_latest.sh" in manifest["entrypoints"]
    assert "ops/deploy/fetch_remote_artifacts.sh" in manifest["entrypoints"]
    assert "ops/deploy/easy_install.sh" in manifest["entrypoints"]
    assert "ops/deploy/install_bundle.sh" in manifest["entrypoints"]
    assert "ops/deploy/run_remote_ranctl.sh" in manifest["entrypoints"]
    assert "ops/deploy/ship_bundle.sh" in manifest["entrypoints"]
    assert manifest["installer_path"] == "artifacts/releases/bootstrap-test/install_bundle.sh"
    assert File.exists?(result.installer_path)

    assert {:ok, table} = :erl_tar.table(String.to_charlist(result.tarball_path), [:compressed])

    assert ~c"README.md" in table
    assert ~c"bin/ran-debug-latest" in table
    assert ~c"bin/ran-install" in table
    assert ~c"bin/ranctl" in table
    assert ~c"bin/ran-deploy-wizard" in table
    assert ~c"bin/ran-fetch-remote-artifacts" in table
    assert ~c"bin/ran-host-preflight" in table
    assert ~c"bin/ran-remote-ranctl" in table
    assert ~c"bin/ran-ship-bundle" in table
    assert ~c"docs/architecture/00-system-overview.md" in table
    assert ~c"ops/deploy/debug_latest.sh" in table
    assert ~c"ops/deploy/fetch_remote_artifacts.sh" in table
    assert ~c"ops/deploy/easy_install.sh" in table
    assert ~c"ops/deploy/run_remote_ranctl.sh" in table
    assert ~c"ops/deploy/ship_bundle.sh" in table
    assert ~c"ops/deploy/preflight.sh" in table
    assert ~c"artifacts/releases/bootstrap-test/manifest.json" in table
  end

  defp write_fixture(repo_root, relative_path, body) do
    path = Path.join(repo_root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end
end
