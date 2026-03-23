defmodule RanActionGateway.ReleaseBundle do
  @moduledoc """
  Builds a bootstrap source bundle with manifest and release-time config checks.
  """

  alias RanActionGateway.Store

  @include_roots [
    ".github/workflows",
    "AGENTS.md",
    "README.md",
    "mix.exs",
    "bin",
    "apps",
    "config",
    "docs",
    "examples",
    "native",
    "ops"
  ]

  @spec build(keyword()) :: {:ok, map()} | {:error, map()}
  def build(opts \\ []) do
    repo_root = Path.expand(Keyword.get(opts, :repo_root, File.cwd!()))

    output_root =
      Path.expand(
        Keyword.get(opts, :output_root, Path.join(Store.artifact_root(), "releases")),
        repo_root
      )

    release_report = RanConfig.release_readiness()

    with :ok <- ensure_release_ready(release_report) do
      bundle_id = Keyword.get(opts, :bundle_id, default_bundle_id(release_report.profile))
      bundle_dir = Path.join(output_root, bundle_id)
      tarball_path = Path.join(bundle_dir, "open_ran_agent-#{bundle_id}.tar.gz")
      manifest_path = Path.join(bundle_dir, "manifest.json")
      installer_path = Path.join(bundle_dir, "install_bundle.sh")

      File.mkdir_p!(bundle_dir)
      copy_installer(repo_root, installer_path)

      included_paths =
        package_paths(repo_root)
        |> Enum.sort()

      manifest =
        %{
          status: "packaged",
          bundle_id: bundle_id,
          release_unit: "bootstrap_source_bundle",
          generated_at: now_iso8601(),
          repo_root: repo_root,
          profile: release_report.profile,
          topology_source: release_report.topology_source,
          entrypoints: [
            "bin/ran-debug-latest",
            "bin/ran-install",
            "bin/ranctl",
            "bin/ran-dashboard",
            "bin/ran-deploy-wizard",
            "bin/ran-fetch-remote-artifacts",
            "bin/ran-host-preflight",
            "bin/ran-remote-ranctl",
            "bin/ran-ship-bundle",
            "ops/deploy/debug_latest.sh",
            "ops/deploy/fetch_remote_artifacts.sh",
            "ops/deploy/easy_install.sh",
            "ops/deploy/install_bundle.sh",
            "ops/deploy/run_remote_ranctl.sh",
            "ops/deploy/ship_bundle.sh",
            "ops/deploy/preflight.sh",
            "mix ran.package_bootstrap"
          ],
          installer_path: relative_path(repo_root, installer_path),
          included_roots: @include_roots,
          included_paths_count: length(included_paths) + 1,
          release_readiness: release_report
        }

      write_json(manifest_path, manifest)

      with :ok <-
             create_tarball(repo_root, tarball_path, [
               relative_path(repo_root, manifest_path) | included_paths
             ]) do
        {:ok,
         %{
           status: "packaged",
           bundle_id: bundle_id,
           tarball_path: tarball_path,
           manifest_path: manifest_path,
           installer_path: installer_path,
           included_paths_count: length(included_paths) + 1,
           release_readiness: release_report
         }}
      else
        {:error, reason} ->
          {:error,
           %{
             status: "tarball_failed",
             bundle_id: bundle_id,
             tarball_path: tarball_path,
             errors: [inspect(reason)]
           }}
      end
    end
  end

  defp ensure_release_ready(%{status: :ok}), do: :ok

  defp ensure_release_ready(report) do
    {:error,
     %{
       status: "release_not_ready",
       release_readiness: report,
       errors: report.errors
     }}
  end

  defp package_paths(repo_root) do
    @include_roots
    |> Enum.flat_map(&expand_root(repo_root, &1))
    |> Enum.uniq()
  end

  defp expand_root(repo_root, path) do
    absolute_path = Path.join(repo_root, path)

    cond do
      File.regular?(absolute_path) ->
        [path]

      File.dir?(absolute_path) ->
        absolute_path
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&relative_path(repo_root, &1))

      true ->
        []
    end
  end

  defp relative_path(repo_root, path) do
    Path.relative_to(Path.expand(path), repo_root)
  end

  defp create_tarball(repo_root, tarball_path, files) do
    {_, exit_code} = System.cmd("tar", ["-czf", tarball_path | files], cd: repo_root)

    case exit_code do
      0 -> :ok
      code -> {:error, {:tar_failed, code}}
    end
  end

  defp write_json(path, payload) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, JSON.encode!(payload))
  end

  defp copy_installer(repo_root, installer_path) do
    source = Path.join(repo_root, "ops/deploy/install_bundle.sh")

    if File.exists?(source) do
      installer_path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.cp!(source, installer_path)
      File.chmod!(installer_path, 0o755)
    end
  end

  defp default_bundle_id(profile) do
    suffix =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    "bootstrap-#{profile}-#{suffix}"
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
