defmodule RanObservability.Dashboard.DeployRunner do
  @moduledoc """
  Wraps the target-host deployment wizard for dashboard-safe preview and preflight flows.
  """

  alias RanObservability.CommandRunner

  @string_fields [
    :bundle_tarball,
    :deploy_profile,
    :install_root,
    :etc_root,
    :systemd_dir,
    :current_root,
    :repo_profile,
    :cell_group,
    :du_id,
    :default_backend,
    :failover_target,
    :scheduler,
    :oai_repo_root,
    :du_conf_path,
    :cucp_conf_path,
    :cuup_conf_path,
    :project_name,
    :fronthaul_session,
    :host_interface,
    :device_path,
    :pci_bdf,
    :dashboard_host,
    :dashboard_port,
    :mix_env,
    :target_host,
    :ssh_user,
    :ssh_port,
    :remote_bundle_dir,
    :remote_install_root,
    :remote_etc_root,
    :remote_systemd_dir
  ]
  @boolean_fields [:strict_host_probe, :pull_images]

  @spec defaults() :: map()
  def defaults do
    repo_root = repo_root()
    preview_root = Path.join(repo_root, "artifacts/deploy_preview")
    install_root = Path.join(preview_root, "install")
    etc_root = Path.join(preview_root, "etc")
    cell_group = List.first(RanConfig.cell_groups())
    cell_group_id = fetch_value(cell_group, :id, "cg-001")
    du_id = fetch_value(cell_group, :du, "du-prod-001")
    backend = fetch_value(cell_group, :backend, :local_fapi_profile) |> to_string()
    scheduler = fetch_value(cell_group, :scheduler, :cpu_scheduler) |> to_string()

    %{
      mode: "preview",
      safe_preview_root: preview_root,
      summary:
        "Generate target-host files into repo-local staging before copying the bundle to a live server.",
      bundle_tarball: latest_bundle_tarball(repo_root),
      deploy_profile: RanConfig.DeployProfiles.default_profile(),
      install_root: install_root,
      etc_root: etc_root,
      systemd_dir: Path.join(preview_root, "systemd"),
      current_root: repo_root,
      repo_profile: "prod_target_host_rfsim",
      cell_group: cell_group_id,
      du_id: du_id,
      default_backend: backend,
      failover_target: failover_target(cell_group, backend),
      scheduler: scheduler,
      oai_repo_root: "/opt/openairinterface5g",
      du_conf_path: Path.join(etc_root, "oai/gnb-du.conf"),
      cucp_conf_path: Path.join(etc_root, "oai/gnb-cucp.conf"),
      cuup_conf_path: Path.join(etc_root, "oai/gnb-cuup.conf"),
      project_name: "ran-oai-du-#{cell_group_id}",
      fronthaul_session: "fh-#{cell_group_id}",
      host_interface: suggested_interface(),
      device_path: "/dev/fh0",
      pci_bdf: "0000:17:00.3",
      dashboard_host: Application.get_env(:ran_observability, :dashboard_host, "127.0.0.1"),
      dashboard_port:
        Application.get_env(:ran_observability, :dashboard_port, 4050) |> to_string(),
      mix_env: System.get_env("MIX_ENV") || "dev",
      target_host: "",
      ssh_user: System.get_env("USER") || "ranops",
      ssh_port: "22",
      remote_bundle_dir: "/tmp/open-ran-agent",
      remote_install_root: "/opt/open-ran-agent",
      remote_etc_root: "/etc/open-ran-agent",
      remote_systemd_dir: "/opt/open-ran-agent/systemd",
      strict_host_probe: true,
      pull_images: false,
      run_precheck: false
    }
  end

  @spec run(map()) :: {:ok, map()} | {:error, map()}
  def run(payload) when is_map(payload) do
    mode = mode(payload)
    config = Map.merge(defaults(), normalize_config(Map.get(payload, "config", %{})))
    args = build_args(config, mode)

    with {:ok, {output, exit_code}} <- run_wizard(args),
         {:ok, result} <- decode_result(output),
         :ok <- ensure_exit_status(exit_code, result) do
      {:ok,
       %{
         status: "ok",
         mode: mode,
         executed_at: now_iso8601(),
         config: summarize_config(config),
         result: result
       }}
    end
  end

  def defaults_payload do
    payload = defaults()

    %{
      status: "ok",
      safe_preview_root: payload.safe_preview_root,
      defaults: payload,
      profile_catalog: RanConfig.DeployProfiles.catalog(),
      recommended_actions: [
        "preview",
        "review-readiness",
        "preflight",
        "handoff",
        "remote-ranctl",
        "fetchback"
      ]
    }
  end

  defp mode(%{"mode" => mode}) when mode in ["preview", "preflight"], do: mode
  defp mode(_payload), do: "preview"

  defp build_args(config, mode) do
    base_args = ["--json", "--defaults", "--skip-install"]

    string_args =
      Enum.flat_map(@string_fields, fn key ->
        case Map.get(config, key) do
          nil -> []
          "" -> []
          value -> ["--#{option_name(key)}", to_string(value)]
        end
      end)

    boolean_args =
      Enum.flat_map(@boolean_fields, fn key ->
        case Map.get(config, key) do
          true -> ["--#{option_name(key)}"]
          false -> ["--no-#{option_name(key)}"]
          _ -> []
        end
      end)

    preflight_args =
      if mode == "preflight" do
        ["--run-precheck"]
      else
        []
      end

    base_args ++ string_args ++ boolean_args ++ preflight_args
  end

  defp summarize_config(config) do
    Map.take(config, [
      :bundle_tarball,
      :deploy_profile,
      :install_root,
      :etc_root,
      :current_root,
      :cell_group,
      :default_backend,
      :failover_target,
      :host_interface,
      :device_path,
      :pci_bdf,
      :target_host,
      :ssh_user,
      :ssh_port,
      :remote_bundle_dir,
      :remote_install_root,
      :remote_etc_root,
      :remote_systemd_dir,
      :dashboard_port,
      :strict_host_probe
    ])
  end

  defp run_wizard(args) do
    {:ok, runner().run(wizard_path(), args, [])}
  rescue
    error in ErlangError ->
      {:error,
       %{
         status: "dashboard_deploy_exec_failed",
         errors: [Exception.message(error)],
         command: wizard_path()
       }}
  end

  defp runner do
    Application.get_env(:ran_observability, :dashboard_command_runner, CommandRunner)
  end

  defp wizard_path do
    Path.expand("../../../../../bin/ran-deploy-wizard", __DIR__)
  end

  defp decode_result(output) do
    case decode_json_candidates(output) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, reason} ->
        {:error, %{status: "invalid_deploy_response", errors: [inspect(reason)]}}
    end
  end

  defp decode_json_candidates(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.find_value(fn candidate ->
      case JSON.decode(candidate) do
        {:ok, payload} -> {:ok, payload}
        {:error, _reason} -> nil
      end
    end)
    |> case do
      nil -> JSON.decode(output)
      result -> result
    end
  end

  defp ensure_exit_status(0, _result), do: :ok
  defp ensure_exit_status(_exit_code, result), do: {:error, result}

  defp latest_bundle_tarball(repo_root) do
    repo_root
    |> Path.join("artifacts/releases/*/open_ran_agent-*.tar.gz")
    |> Path.wildcard()
    |> Enum.sort_by(&File.stat!(&1).mtime, :desc)
    |> List.first()
  rescue
    _error -> nil
  end

  defp failover_target(nil, current_backend), do: fallback_failover_target(current_backend)

  defp failover_target(cell_group, current_backend) do
    targets =
      cell_group
      |> fetch_value(:failover_targets, [])
      |> Enum.map(&to_string/1)

    Enum.find(targets, &(&1 != current_backend)) || List.first(targets) ||
      fallback_failover_target(current_backend)
  end

  defp fallback_failover_target("aerial_fapi_profile"), do: "local_fapi_profile"
  defp fallback_failover_target(_backend), do: "aerial_fapi_profile"

  defp suggested_interface do
    interfaces =
      "/sys/class/net/*"
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)

    cond do
      "sync0" in interfaces -> "sync0"
      "lo" in interfaces -> "lo"
      interfaces != [] -> hd(interfaces)
      true -> "lo"
    end
  end

  defp repo_root do
    Path.expand("../../../../../", __DIR__)
  end

  defp option_name(key) do
    case key do
      :bundle_tarball ->
        "bundle"

      _other ->
        key
        |> Atom.to_string()
        |> String.replace("_", "-")
    end
  end

  defp normalize_config(config) when is_map(config) do
    Enum.reduce(config, %{}, fn
      {key, value}, acc when is_binary(key) ->
        case safe_existing_atom(key) do
          {:ok, atom_key} -> Map.put(acc, atom_key, value)
          :error -> acc
        end

      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)

      _entry, acc ->
        acc
    end)
  end

  defp safe_existing_atom(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end

  defp fetch_value(nil, _key, default), do: default
  defp fetch_value(map, key, default), do: Map.get(map, key, default)

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
