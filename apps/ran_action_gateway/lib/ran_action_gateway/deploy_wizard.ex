defmodule RanActionGateway.DeployWizard do
  @moduledoc """
  Interactive target-host deployment wizard for the bootstrap bundle.
  """

  alias RanConfig.DeployProfiles

  @default_install_root "/opt/open-ran-agent"
  @default_etc_root "/etc/open-ran-agent"
  @default_oai_root "/opt/openairinterface5g"
  @string_option_fields [
    bundle: :bundle_tarball,
    deploy_profile: :deploy_profile,
    install_root: :install_root,
    etc_root: :etc_root,
    systemd_dir: :systemd_dir,
    current_root: :current_root,
    repo_profile: :repo_profile,
    cell_group: :cell_group,
    du_id: :du_id,
    default_backend: :default_backend,
    failover_target: :failover_target,
    scheduler: :scheduler,
    oai_repo_root: :oai_repo_root,
    du_conf_path: :du_conf_path,
    cucp_conf_path: :cucp_conf_path,
    cuup_conf_path: :cuup_conf_path,
    project_name: :project_name,
    fronthaul_session: :fronthaul_session,
    host_interface: :host_interface,
    device_path: :device_path,
    pci_bdf: :pci_bdf,
    dashboard_host: :dashboard_host,
    dashboard_port: :dashboard_port,
    mix_env: :mix_env,
    target_host: :target_host,
    ssh_user: :ssh_user,
    ssh_port: :ssh_port,
    remote_bundle_dir: :remote_bundle_dir,
    remote_install_root: :remote_install_root,
    remote_etc_root: :remote_etc_root,
    remote_systemd_dir: :remote_systemd_dir
  ]
  @boolean_option_fields [
    pull_images: :pull_images,
    strict_host_probe: :strict_host_probe
  ]

  @type result :: {:ok, map()} | {:error, map()}

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    json? = "--json" in argv

    case run(argv) do
      {:ok, payload} ->
        if json?, do: IO.puts(JSON.encode!(payload)), else: render_success(payload)
        System.halt(0)

      {:error, payload} ->
        if json?, do: IO.puts(JSON.encode!(payload)), else: render_error(payload)
        System.halt(1)
    end
  end

  @spec run([String.t()]) :: result()
  def run(argv) do
    with {:ok, opts} <- parse_options(argv),
         defaults = default_config(opts),
         {:ok, config} <- collect_config(defaults, opts),
         :ok <- maybe_install_bundle(config),
         {:ok, files} <- write_target_host_files(config),
         {:ok, preflight} <- maybe_run_preflight(config),
         readiness = deployment_readiness(config, files, preflight),
         {:ok, files} <- write_readiness_file(config, files, readiness),
         previews = load_file_previews(files) do
      {:ok,
       %{
         status: "configured",
         mode: if(opts[:defaults], do: "defaults", else: "interactive"),
         install_performed: config.install_bundle,
         bundle_tarball: config.bundle_tarball,
         current_root: config.current_root,
         etc_root: config.etc_root,
         files: files,
         previews: previews,
         readiness: readiness,
         handoff: handoff_plan(config, files),
         next_steps: next_steps(config, files, preflight, readiness),
         preflight: preflight
       }}
    end
  end

  @spec write_target_host_files(map()) :: {:ok, map()} | {:error, map()}
  def write_target_host_files(config) when is_map(config) do
    topology_path = Path.join(config.etc_root, "topology.single_du.target_host.rfsim.json")
    request_dir = Path.join(config.etc_root, "requests")
    request_path = Path.join(request_dir, "precheck-target-host.json")
    dashboard_env_path = Path.join(config.etc_root, "ran-dashboard.env")
    preflight_env_path = Path.join(config.etc_root, "ran-host-preflight.env")
    profile_path = Path.join(config.etc_root, "deploy.profile.json")
    effective_config_path = Path.join(config.etc_root, "deploy.effective.json")
    request_payloads = render_request_payloads(config)
    request_paths = request_bundle_paths(request_dir)

    File.mkdir_p!(Path.dirname(topology_path))
    File.mkdir_p!(request_dir)

    File.write!(topology_path, JSON.encode!(render_topology(config)))

    Enum.each(request_paths, fn {key, path} ->
      File.write!(path, JSON.encode!(Map.fetch!(request_payloads, key)))
    end)

    File.write!(dashboard_env_path, render_dashboard_env(config, topology_path))
    File.write!(preflight_env_path, render_preflight_env(config, topology_path, request_path))
    File.write!(profile_path, JSON.encode!(render_profile_manifest(config)))

    File.write!(
      effective_config_path,
      JSON.encode!(render_effective_config(config, topology_path, request_path))
    )

    {:ok,
     %{
       topology_path: topology_path,
       request_path: request_path,
       request_paths: request_paths,
       dashboard_env_path: dashboard_env_path,
       preflight_env_path: preflight_env_path,
       profile_path: profile_path,
       effective_config_path: effective_config_path
     }}
  rescue
    error ->
      {:error, %{status: "wizard_write_failed", errors: [Exception.message(error)]}}
  end

  defp write_readiness_file(config, files, readiness) do
    readiness_path = Path.join(config.etc_root, "deploy.readiness.json")
    File.write!(readiness_path, JSON.encode!(readiness))
    {:ok, Map.put(files, :readiness_path, readiness_path)}
  rescue
    error ->
      {:error, %{status: "wizard_readiness_write_failed", errors: [Exception.message(error)]}}
  end

  @spec render_topology(map()) :: map()
  def render_topology(config) do
    %{
      "repo_profile" => config.repo_profile,
      "default_backend" => config.default_backend,
      "scheduler_adapter" => config.scheduler,
      "cell_groups" => [
        %{
          "id" => config.cell_group,
          "du" => config.du_id,
          "backend" => config.default_backend,
          "deploy_profile" => config.deploy_profile,
          "failover_targets" => [config.failover_target],
          "scheduler" => config.scheduler,
          "oai_runtime" => %{
            "mode" => "docker_compose_rfsim_f1",
            "repo_root" => config.oai_repo_root,
            "du_conf_path" => config.du_conf_path,
            "cucp_conf_path" => config.cucp_conf_path,
            "cuup_conf_path" => config.cuup_conf_path,
            "project_name" => config.project_name,
            "pull_images" => config.pull_images
          }
        }
      ]
    }
  end

  @spec render_request(map()) :: map()
  def render_request(config), do: Map.fetch!(render_request_payloads(config), :precheck)

  defp render_request_payloads(config) do
    %{
      precheck: render_precheck_request(config),
      plan: render_plan_request(config),
      verify: render_verify_request(config),
      rollback: render_rollback_request(config)
    }
  end

  defp request_bundle_paths(request_dir) do
    %{
      precheck: Path.join(request_dir, "precheck-target-host.json"),
      plan: Path.join(request_dir, "plan-gnb-bringup.json"),
      verify: Path.join(request_dir, "verify-attach-ping.json"),
      rollback: Path.join(request_dir, "rollback-gnb-cutover.json")
    }
  end

  defp render_precheck_request(config) do
    %{
      "scope" => "target_host",
      "target_ref" => replacement_host_target_ref(config),
      "target_backend" => "replacement_shadow",
      "rollback_target" => "oai_reference",
      "change_id" => "chg-ran-repl-precheck-001",
      "reason" => "precheck declared n79 replacement lane on the target host",
      "idempotency_key" => "ran-repl-precheck-001",
      "ttl" => "20m",
      "dry_run" => false,
      "verify_window" => %{
        "duration" => "30s",
        "checks" => ["host_preflight", "ru_sync", "core_link_reachable"]
      },
      "max_blast_radius" => "single_lab",
      "metadata" => %{
        "deploy_profile" => render_profile_summary(config),
        "native_probe" => %{
          "backend_profile" => config.default_backend,
          "session_payload" => %{
            "fronthaul_session" => config.fronthaul_session,
            "host_interface" => config.host_interface,
            "device_path" => config.device_path,
            "pci_bdf" => config.pci_bdf,
            "strict_host_probe" => config.strict_host_probe
          }
        },
        "replacement" =>
          replacement_metadata_payload(config, %{
            "target_role" => "target_host",
            "action" => "precheck",
            "desired_state" => "present",
            "cutover_mode" => "none",
            "required_interfaces" => [
              "ngap",
              "f1_c",
              "f1_u",
              "e1ap",
              "gtpu",
              "ru_fronthaul",
              "ptp"
            ],
            "acceptance_gates" => [
              "host_preflight",
              "ru_sync",
              "registration",
              "pdu_session",
              "ping"
            ]
          })
      }
    }
  end

  defp render_plan_request(config) do
    %{
      "scope" => "gnb",
      "target_ref" => replacement_gnb_target_ref(config),
      "target_backend" => "replacement_shadow",
      "current_backend" => "oai_reference",
      "rollback_target" => "oai_reference",
      "change_id" => "chg-ran-repl-bringup-001",
      "reason" => "plan declared n79 replacement bring-up against the real target host lane",
      "idempotency_key" => "ran-repl-bringup-001",
      "ttl" => "30m",
      "dry_run" => false,
      "verify_window" => %{
        "duration" => "60s",
        "checks" => ["host_preflight", "ru_sync", "ngap_reachable", "registration_path_ready"]
      },
      "max_blast_radius" => "single_gnb",
      "metadata" => %{
        "deploy_profile" => render_profile_summary(config),
        "replacement" =>
          replacement_metadata_payload(config, %{
            "target_role" => "gnb",
            "action" => "bring_up",
            "desired_state" => "shadow",
            "cutover_mode" => "shadow",
            "required_interfaces" => [
              "ngap",
              "f1_c",
              "f1_u",
              "e1ap",
              "gtpu",
              "ru_fronthaul",
              "ptp"
            ],
            "acceptance_gates" => [
              "host_preflight",
              "ru_sync",
              "registration",
              "pdu_session",
              "ping"
            ]
          })
      }
    }
  end

  defp render_verify_request(config) do
    %{
      "scope" => "ue_session",
      "target_ref" => replacement_ue_target_ref(config),
      "target_backend" => "replacement_shadow",
      "current_backend" => "oai_reference",
      "rollback_target" => "oai_reference",
      "change_id" => "chg-ran-repl-verify-001",
      "incident_id" => "inc-ran-repl-verify-001",
      "reason" =>
        "verify attach, registration, PDU session, and ping on the declared n79 replacement lane",
      "idempotency_key" => "ran-repl-verify-001",
      "ttl" => "20m",
      "dry_run" => false,
      "verify_window" => %{
        "duration" => "120s",
        "checks" => ["registration_complete", "pdu_session_established", "ping_success"]
      },
      "max_blast_radius" => "single_ue",
      "metadata" => %{
        "deploy_profile" => render_profile_summary(config),
        "replacement" =>
          replacement_metadata_payload(config, %{
            "target_role" => "ue_session",
            "action" => "verify_attach_ping",
            "desired_state" => "active",
            "cutover_mode" => "shadow",
            "required_interfaces" => ["ngap", "f1_u", "gtpu", "ru_fronthaul"],
            "acceptance_gates" => ["registration", "pdu_session", "ping"]
          })
      }
    }
  end

  defp render_rollback_request(config) do
    %{
      "scope" => "replacement_cutover",
      "target_ref" => replacement_gnb_target_ref(config),
      "target_backend" => "oai_reference",
      "current_backend" => "replacement_primary",
      "rollback_target" => "oai_reference",
      "change_id" => "chg-ran-repl-rollback-001",
      "incident_id" => "inc-ran-repl-rollback-001",
      "reason" => "rollback the declared n79 replacement lane after a failed real-lab proof",
      "idempotency_key" => "ran-repl-rollback-001",
      "ttl" => "20m",
      "dry_run" => false,
      "verify_window" => %{
        "duration" => "45s",
        "checks" => ["rollback_target_known", "approval_evidence_present", "oai_reference_ready"]
      },
      "max_blast_radius" => "single_gnb",
      "metadata" => %{
        "deploy_profile" => render_profile_summary(config),
        "replacement" =>
          replacement_metadata_payload(config, %{
            "target_role" => "gnb",
            "action" => "rollback",
            "desired_state" => "present",
            "cutover_mode" => "rollback",
            "destructive" => true,
            "required_interfaces" => [
              "ngap",
              "f1_c",
              "f1_u",
              "e1ap",
              "gtpu",
              "ru_fronthaul",
              "ptp"
            ],
            "acceptance_gates" => ["registration", "pdu_session", "ping"]
          })
      }
    }
  end

  defp replacement_metadata_payload(config, overrides) do
    base = %{
      "target_profile" => "n79_single_ru_single_ue_lab_v1",
      "core_profile" => "open5gs_nsa_lab_v1",
      "band" => "n79",
      "plane_scope" => ["s_plane", "m_plane", "c_plane", "u_plane"],
      "allow_oai_fallback" => true,
      "destructive" => false,
      "real_ru_required" => true,
      "real_ue_required" => true,
      "open5gs_core" => %{
        "profile" => "open5gs_nsa_lab_v1",
        "release_ref" => "open5gs-sanitized-lab-release-1",
        "n2" => %{"amf_host" => "10.41.83.45", "amf_port" => 38412, "bind_host" => "10.41.83.34"},
        "n3" => %{
          "upf_host" => "10.41.83.45",
          "gtpu_port" => 2152,
          "dnn" => "internet",
          "slice" => %{"sst" => 1, "sd" => "000001"}
        },
        "subscriber_profile" => %{"imsi_ref" => "sanitized-imsi-001", "ue_class" => "n79_lab_ue"},
        "session_profile" => %{"pdu_type" => "ipv4", "expect_ping_target" => "8.8.8.8"}
      },
      "native_probe" => %{
        "strict_host_probe" => config.strict_host_probe,
        "required_resources" => [config.host_interface, config.device_path, config.pci_bdf]
      },
      "ngap_subset" => %{
        "standards_subset_ref" =>
          "subprojects/ran_replacement/notes/06-ngap-and-registration-standards-subset.md",
        "procedure_matrix_ref" =>
          "subprojects/ran_replacement/notes/09-ngap-procedure-support-matrix.md",
        "required_procedures" => [
          "NG Setup",
          "Initial UE Message",
          "Uplink NAS Transport",
          "Downlink NAS Transport",
          "UE Context Release"
        ],
        "optional_procedures" => ["Error Indication", "Reset"],
        "deferred_procedures" => ["Paging", "Handover Preparation", "Path Switch Request"]
      }
    }

    Map.merge(base, overrides)
  end

  defp replacement_host_target_ref(config) do
    if blank?(config.target_host), do: "host-#{config.cell_group}", else: config.target_host
  end

  defp replacement_gnb_target_ref(config), do: "gnb-#{config.cell_group}"
  defp replacement_ue_target_ref(config), do: "ue-#{config.cell_group}"

  @spec render_dashboard_env(map(), Path.t()) :: String.t()
  def render_dashboard_env(config, topology_path) do
    config
    |> render_dashboard_env_map(topology_path)
    |> render_env_file()
  end

  @spec render_preflight_env(map(), Path.t(), Path.t()) :: String.t()
  def render_preflight_env(config, topology_path, request_path) do
    config
    |> render_preflight_env_map(topology_path, request_path)
    |> render_env_file()
  end

  defp parse_options(argv) do
    {opts, rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          bundle: :string,
          deploy_profile: :string,
          install_root: :string,
          etc_root: :string,
          systemd_dir: :string,
          current_root: :string,
          repo_profile: :string,
          cell_group: :string,
          du_id: :string,
          default_backend: :string,
          failover_target: :string,
          scheduler: :string,
          oai_repo_root: :string,
          du_conf_path: :string,
          cucp_conf_path: :string,
          cuup_conf_path: :string,
          project_name: :string,
          fronthaul_session: :string,
          host_interface: :string,
          device_path: :string,
          pci_bdf: :string,
          dashboard_host: :string,
          dashboard_port: :string,
          mix_env: :string,
          target_host: :string,
          ssh_user: :string,
          ssh_port: :string,
          remote_bundle_dir: :string,
          remote_install_root: :string,
          remote_etc_root: :string,
          remote_systemd_dir: :string,
          defaults: :boolean,
          safe_preview: :boolean,
          skip_install: :boolean,
          run_precheck: :boolean,
          pull_images: :boolean,
          strict_host_probe: :boolean,
          json: :boolean
        ]
      )

    cond do
      invalid != [] ->
        {:error, %{status: "invalid_wizard_options", invalid: invalid}}

      rest != [] ->
        {:error, %{status: "unexpected_arguments", arguments: rest}}

      true ->
        {:ok, opts}
    end
  end

  defp default_config(opts) do
    {install_root, etc_root, systemd_dir, current_root} =
      preview_roots(opts)

    base_config = %{
      bundle_tarball: latest_bundle_tarball(),
      deploy_profile: DeployProfiles.default_profile(),
      install_root: install_root,
      systemd_dir: systemd_dir,
      current_root: current_root,
      etc_root: etc_root,
      repo_profile: "prod_target_host_rfsim",
      cell_group: "cg-001",
      du_id: "du-prod-001",
      default_backend: "local_fapi_profile",
      failover_target: "aerial_fapi_profile",
      scheduler: "cpu_scheduler",
      oai_repo_root: @default_oai_root,
      du_conf_path: Path.join(etc_root, "oai/gnb-du.conf"),
      cucp_conf_path: Path.join(etc_root, "oai/gnb-cucp.conf"),
      cuup_conf_path: Path.join(etc_root, "oai/gnb-cuup.conf"),
      project_name: "ran-oai-du-cg-001",
      pull_images: false,
      fronthaul_session: "fh-prod-001",
      host_interface: suggested_interface(),
      device_path: "/dev/fh0",
      pci_bdf: "0000:17:00.3",
      strict_host_probe: true,
      dashboard_host: "0.0.0.0",
      dashboard_port: "4050",
      mix_env: "prod",
      target_host: "",
      ssh_user: System.get_env("USER") || "ranops",
      ssh_port: "22",
      remote_bundle_dir: "/tmp/open-ran-agent",
      remote_install_root: @default_install_root,
      remote_etc_root: @default_etc_root,
      remote_systemd_dir: Path.join(@default_install_root, "systemd"),
      install_bundle: not opts[:skip_install],
      run_precheck: opts[:run_precheck] || false
    }

    selected_profile = opts[:deploy_profile] || base_config.deploy_profile

    with_profile =
      case DeployProfiles.apply_config(base_config, selected_profile) do
        {:ok, config} -> config
        {:error, _payload} -> Map.put(base_config, :deploy_profile, selected_profile)
      end

    apply_option_overrides(with_profile, opts)
  end

  defp collect_config(defaults, opts) do
    if opts[:defaults] do
      validate_config(defaults)
    else
      config =
        defaults
        |> prompt_field(:deploy_profile, "Deploy profile")
        |> maybe_apply_profile()
        |> prompt_field(:bundle_tarball, "Bundle tarball")
        |> prompt_bool(:install_bundle, "Install bundle now")
        |> prompt_field(:install_root, "Install root")
        |> prompt_field(:current_root, "Current checkout path")
        |> prompt_field(:etc_root, "Operator config root")
        |> prompt_field(:systemd_dir, "Systemd staging dir")
        |> prompt_field(:repo_profile, "Repo profile")
        |> prompt_field(:cell_group, "Cell group id")
        |> prompt_field(:du_id, "DU id")
        |> prompt_field(:default_backend, "Default backend profile")
        |> prompt_field(:failover_target, "Failover target")
        |> prompt_field(:scheduler, "Scheduler adapter")
        |> prompt_field(:oai_repo_root, "OAI repo root")
        |> prompt_field(:du_conf_path, "DU conf path")
        |> prompt_field(:cucp_conf_path, "CUCP conf path")
        |> prompt_field(:cuup_conf_path, "CUUP conf path")
        |> prompt_field(:project_name, "Compose project name")
        |> prompt_bool(:pull_images, "Pull images during apply")
        |> prompt_field(:fronthaul_session, "Fronthaul session id")
        |> prompt_field(:host_interface, "Host interface")
        |> prompt_field(:device_path, "Device path")
        |> prompt_field(:pci_bdf, "PCI BDF")
        |> prompt_bool(:strict_host_probe, "Strict native probe gate")
        |> prompt_field(:dashboard_host, "Dashboard host")
        |> prompt_field(:dashboard_port, "Dashboard port")
        |> prompt_field(:target_host, "Target host")
        |> prompt_field(:ssh_user, "SSH user")
        |> prompt_field(:ssh_port, "SSH port")
        |> prompt_field(:remote_bundle_dir, "Remote bundle dir")
        |> prompt_field(:remote_install_root, "Remote install root")
        |> prompt_field(:remote_etc_root, "Remote config root")
        |> prompt_field(:remote_systemd_dir, "Remote systemd dir")
        |> prompt_bool(:run_precheck, "Run precheck after writing files")

      validate_config(config)
    end
  end

  defp validate_config(config) do
    cond do
      config.install_bundle and blank?(config.bundle_tarball) ->
        {:error, %{status: "wizard_bundle_required", errors: ["bundle tarball is required"]}}

      match?({:error, _payload}, DeployProfiles.profile(config.deploy_profile)) ->
        {:error,
         %{
           status: "wizard_invalid_deploy_profile",
           errors: ["deploy_profile is invalid"],
           deploy_profile: config.deploy_profile,
           known_profiles: Enum.map(DeployProfiles.catalog(), & &1.name)
         }}

      blank?(config.current_root) ->
        {:error, %{status: "wizard_current_root_required", errors: ["current_root is required"]}}

      true ->
        {:ok, config}
    end
  end

  defp prompt_field(config, key, label) do
    current = Map.fetch!(config, key)
    answer = prompt("#{label} [#{current}]: ")
    Map.put(config, key, if(blank?(answer), do: current, else: answer))
  end

  defp prompt_bool(config, key, label) do
    current = Map.fetch!(config, key)
    hint = if(current, do: "Y/n", else: "y/N")

    answer =
      prompt("#{label} [#{hint}]: ")
      |> String.trim()
      |> String.downcase()

    value =
      case answer do
        "" -> current
        "y" -> true
        "yes" -> true
        "n" -> false
        "no" -> false
        _ -> current
      end

    Map.put(config, key, value)
  end

  defp maybe_install_bundle(%{install_bundle: false}), do: :ok

  defp maybe_install_bundle(config) do
    installer = Path.expand("ops/deploy/install_bundle.sh", File.cwd!())

    env = [
      {"RAN_ETC_ROOT", config.etc_root},
      {"RAN_SYSTEMD_STAGING_DIR", config.systemd_dir}
    ]

    case System.cmd("bash", [installer, config.bundle_tarball, config.install_root], env: env) do
      {_output, 0} ->
        :ok

      {output, code} ->
        {:error, %{status: "wizard_install_failed", exit_code: code, output: output}}
    end
  end

  defp maybe_run_preflight(%{run_precheck: false}), do: {:ok, nil}

  defp maybe_run_preflight(config) do
    cmd = Path.join(config.current_root, "bin/ran-host-preflight")

    env = [
      {"MIX_ENV", config.mix_env},
      {"RAN_REPO_ROOT", config.current_root},
      {"RAN_TOPOLOGY_FILE",
       Path.join(config.etc_root, "topology.single_du.target_host.rfsim.json")},
      {"RAN_PREFLIGHT_REQUEST", Path.join(config.etc_root, "requests/precheck-target-host.json")}
    ]

    case System.cmd(cmd, [], env: env, stderr_to_stdout: true) do
      {output, code} ->
        payload = %{
          status: infer_preflight_status(output, code),
          exit_code: code,
          output: output
        }

        {:ok, maybe_attach_preflight_response(payload, output)}
    end
  rescue
    error ->
      {:error, %{status: "wizard_preflight_failed", errors: [Exception.message(error)]}}
  end

  defp latest_bundle_tarball do
    "artifacts/releases/*/open_ran_agent-*.tar.gz"
    |> Path.wildcard()
    |> Enum.sort_by(&File.stat!(&1).mtime, &>=/2)
    |> List.first()
  rescue
    _error -> nil
  end

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

  defp render_success(payload) do
    IO.puts(IO.ANSI.format([:green, "Target-host deployment configured", :reset]))
    IO.puts("Current root: #{payload.current_root}")
    IO.puts("Config root : #{payload.etc_root}")
    IO.puts("Topology    : #{payload.files.topology_path}")
    IO.puts("Request     : #{payload.files.request_path}")
    IO.puts("Dashboard env: #{payload.files.dashboard_env_path}")
    IO.puts("Preflight env: #{payload.files.preflight_env_path}")
    IO.puts("Profile     : #{decode_profile_name(payload.previews.profile_manifest.content)}")
    IO.puts("Readiness   : #{payload.readiness.status} (#{payload.readiness.score})")

    if payload.handoff.enabled do
      IO.puts("Remote host : #{payload.handoff.ssh_target}")
    end

    case payload.preflight do
      nil ->
        IO.puts("Preflight   : skipped")

      %{status: status} ->
        IO.puts("Preflight   : #{status}")
    end
  end

  defp render_error(payload) do
    IO.puts(IO.ANSI.format([:red, "Deployment wizard failed", :reset]))
    IO.puts(JSON.encode!(payload))
  end

  defp prompt(message) do
    IO.write(IO.ANSI.format([:cyan, message, :reset]))
    IO.gets("") |> to_string() |> String.trim_trailing()
  end

  defp apply_option_overrides(config, opts) do
    config
    |> apply_string_option_overrides(opts)
    |> apply_boolean_option_overrides(opts)
  end

  defp apply_string_option_overrides(config, opts) do
    Enum.reduce(@string_option_fields, config, fn {option_key, config_key}, acc ->
      case opts[option_key] do
        nil -> acc
        value -> Map.put(acc, config_key, value)
      end
    end)
  end

  defp apply_boolean_option_overrides(config, opts) do
    Enum.reduce(@boolean_option_fields, config, fn {option_key, config_key}, acc ->
      if Keyword.has_key?(opts, option_key) do
        Map.put(acc, config_key, opts[option_key])
      else
        acc
      end
    end)
  end

  defp load_file_previews(files) do
    %{
      topology: load_preview(files.topology_path),
      request: load_preview(files.request_path),
      replacement_requests:
        files.request_paths
        |> Enum.reject(fn {key, _path} -> key == :precheck end)
        |> Enum.into(%{}, fn {key, path} -> {key, load_preview(path)} end),
      dashboard_env: load_preview(files.dashboard_env_path),
      preflight_env: load_preview(files.preflight_env_path),
      profile_manifest: load_preview(files.profile_path),
      effective_config: load_preview(files.effective_config_path),
      readiness: load_preview(files.readiness_path)
    }
  end

  defp load_preview(path) do
    case File.read(path) do
      {:ok, body} -> %{path: path, content: body}
      {:error, reason} -> %{path: path, error: inspect(reason)}
    end
  end

  defp next_steps(config, files, preflight, readiness) do
    readiness_steps =
      case readiness.recommendation do
        "fix_blockers" ->
          [
            "Resolve the blockers listed in #{files.readiness_path} before attempting remote apply."
          ]

        "package_bundle" ->
          ["Select or build a bundle tarball before remote handoff."]

        "set_target_host" ->
          [
            "Set target_host, ssh_user, and ssh_port to generate an executable remote handoff plan."
          ]

        "run_preflight" ->
          ["Run host preflight and clear the last gate before shipping the bundle."]

        "ship_bundle" ->
          ["Remote handoff is ready; ship the bundle and start with remote ranctl precheck."]

        _ ->
          []
      end

    profile_steps =
      config.deploy_profile
      |> DeployProfiles.summary()
      |> Map.get(:operator_steps, [])

    generic_steps = [
      "Review #{files.topology_path} and #{files.request_path} before moving the bundle to the target host.",
      "Review the replacement request bundle under #{Path.dirname(files.request_path)} before remote ranctl execution.",
      "Review #{files.readiness_path} for blockers, warnings, and the computed rollout score.",
      "Run #{Path.join(config.current_root, "bin/ran-host-preflight")} with #{files.preflight_env_path} on the target host.",
      "Launch #{Path.join(config.current_root, "bin/ran-dashboard")} with #{files.dashboard_env_path} to expose the operator UI."
    ]

    remote_steps =
      if(blank?(config.target_host),
        do: [],
        else: [
          "Use the generated handoff commands or run #{Path.join(config.current_root, "bin/ran-ship-bundle")} #{config.bundle_tarball} #{config.target_host} from the packaging host.",
          "Drive remote ranctl from the packaging host with #{Path.join(config.current_root, "bin/ran-remote-ranctl")} across precheck, plan, apply, verify, capture-artifacts, and rollback using the generated request bundle.",
          "Re-sync remote evidence on demand with #{Path.join(config.current_root, "bin/ran-fetch-remote-artifacts")} #{config.target_host} and the matching generated request file for the phase you are replaying."
        ]
      )

    preflight_steps =
      case preflight do
        %{status: "ok"} ->
          [
            "Preflight already passed in this preview; proceed to ranctl plan/apply on the target host."
          ]

        %{status: "failed"} ->
          ["Preflight reported failures; inspect the captured output before applying changes."]

        _ ->
          ["Run preflight from Deploy Studio or the CLI wizard before attempting apply."]
      end

    (readiness_steps ++ profile_steps ++ generic_steps ++ remote_steps ++ preflight_steps)
    |> Enum.uniq()
  end

  defp preview_roots(opts) do
    if opts[:safe_preview] do
      repo_root = File.cwd!()
      preview_root = Path.join(repo_root, "artifacts/deploy_preview")
      install_root = opts[:install_root] || Path.join(preview_root, "install")
      etc_root = opts[:etc_root] || Path.join(preview_root, "etc")
      systemd_dir = opts[:systemd_dir] || Path.join(preview_root, "systemd")
      current_root = opts[:current_root] || repo_root
      {install_root, etc_root, systemd_dir, current_root}
    else
      install_root = opts[:install_root] || @default_install_root
      etc_root = opts[:etc_root] || @default_etc_root
      systemd_dir = opts[:systemd_dir] || Path.join(install_root, "systemd")
      current_root = opts[:current_root] || Path.join(install_root, "current")
      {install_root, etc_root, systemd_dir, current_root}
    end
  end

  defp handoff_plan(config, files) do
    installer_path = bundled_installer_path(config.bundle_tarball)
    ssh_target = ssh_target(config)
    remote_bundle_name = maybe_basename(config.bundle_tarball)
    remote_bundle_tarball = remote_path(config.remote_bundle_dir, remote_bundle_name)
    remote_installer = remote_path(config.remote_bundle_dir, "install_bundle.sh")
    remote_topology = remote_path(config.remote_etc_root, Path.basename(files.topology_path))
    remote_request_paths = remote_request_paths(config, files)

    remote_request = Map.fetch!(remote_request_paths, :precheck)

    remote_dashboard_env =
      remote_path(config.remote_etc_root, Path.basename(files.dashboard_env_path))

    remote_preflight_env =
      remote_path(config.remote_etc_root, Path.basename(files.preflight_env_path))

    remote_profile = remote_path(config.remote_etc_root, Path.basename(files.profile_path))

    remote_effective_config =
      remote_path(config.remote_etc_root, Path.basename(files.effective_config_path))

    remote_readiness =
      remote_path(config.remote_etc_root, Path.basename(files.readiness_path))

    %{
      enabled: not blank?(config.target_host),
      target_host: config.target_host,
      ssh_target: ssh_target,
      local_bundle_tarball: config.bundle_tarball,
      local_installer_path: installer_path,
      remote_bundle_dir: config.remote_bundle_dir,
      remote_bundle_tarball: remote_bundle_tarball,
      remote_installer_path: remote_installer,
      remote_topology_path: remote_topology,
      remote_request_path: remote_request,
      remote_request_paths: remote_request_paths,
      remote_dashboard_env_path: remote_dashboard_env,
      remote_preflight_env_path: remote_preflight_env,
      remote_profile_path: remote_profile,
      remote_effective_config_path: remote_effective_config,
      remote_readiness_path: remote_readiness,
      remote_install_root: config.remote_install_root,
      remote_etc_root: config.remote_etc_root,
      remote_systemd_dir: config.remote_systemd_dir,
      remote_ranctl_commands:
        if(blank?(config.target_host),
          do: [],
          else: remote_ranctl_commands(config, files)
        ),
      fetch_commands:
        if(blank?(config.target_host),
          do: [],
          else: fetch_commands(config, files)
        ),
      commands:
        if(blank?(config.target_host),
          do: [],
          else: handoff_commands(config, files, installer_path)
        )
    }
  end

  defp handoff_commands(config, files, installer_path) do
    ssh_port = to_string(config.ssh_port)
    ssh_target = ssh_target(config)
    remote_bundle_dir = config.remote_bundle_dir
    remote_bundle_tarball = remote_path(remote_bundle_dir, maybe_basename(config.bundle_tarball))
    remote_installer = remote_path(remote_bundle_dir, "install_bundle.sh")
    remote_topology = remote_path(config.remote_etc_root, Path.basename(files.topology_path))
    remote_request_paths = remote_request_paths(config, files)
    remote_request = Map.fetch!(remote_request_paths, :precheck)

    remote_dashboard_env =
      remote_path(config.remote_etc_root, Path.basename(files.dashboard_env_path))

    remote_preflight_env =
      remote_path(config.remote_etc_root, Path.basename(files.preflight_env_path))

    remote_profile = remote_path(config.remote_etc_root, Path.basename(files.profile_path))

    remote_effective_config =
      remote_path(config.remote_etc_root, Path.basename(files.effective_config_path))

    remote_readiness =
      remote_path(config.remote_etc_root, Path.basename(files.readiness_path))

    request_copy_commands =
      Enum.map(files.request_paths, fn {key, path} ->
        remote_path = Map.fetch!(remote_request_paths, key)

        "scp -P #{shell_escape(ssh_port)} #{shell_escape(path)} #{shell_escape(ssh_target <> ":" <> remote_path)}"
      end)

    [
      "ssh -p #{shell_escape(ssh_port)} #{shell_escape(ssh_target)} mkdir -p #{shell_escape(remote_bundle_dir)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(config.bundle_tarball)} #{shell_escape(ssh_target <> ":" <> remote_bundle_tarball)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(installer_path)} #{shell_escape(ssh_target <> ":" <> remote_installer)}",
      "ssh -p #{shell_escape(ssh_port)} #{shell_escape(ssh_target)} env RAN_ETC_ROOT=#{shell_escape(config.remote_etc_root)} RAN_SYSTEMD_STAGING_DIR=#{shell_escape(config.remote_systemd_dir)} bash #{shell_escape(remote_installer)} #{shell_escape(remote_bundle_tarball)} #{shell_escape(config.remote_install_root)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(files.topology_path)} #{shell_escape(ssh_target <> ":" <> remote_topology)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(files.dashboard_env_path)} #{shell_escape(ssh_target <> ":" <> remote_dashboard_env)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(files.preflight_env_path)} #{shell_escape(ssh_target <> ":" <> remote_preflight_env)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(files.profile_path)} #{shell_escape(ssh_target <> ":" <> remote_profile)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(files.effective_config_path)} #{shell_escape(ssh_target <> ":" <> remote_effective_config)}",
      "scp -P #{shell_escape(ssh_port)} #{shell_escape(files.readiness_path)} #{shell_escape(ssh_target <> ":" <> remote_readiness)}"
    ] ++
      request_copy_commands ++
      [
        "ssh -p #{shell_escape(ssh_port)} #{shell_escape(ssh_target)} env RAN_REPO_ROOT=#{shell_escape(remote_path(config.remote_install_root, "current"))} RAN_TOPOLOGY_FILE=#{shell_escape(remote_topology)} RAN_PREFLIGHT_REQUEST=#{shell_escape(remote_request)} #{shell_escape(remote_path(config.remote_install_root, "current/bin/ran-host-preflight"))}"
      ]
  end

  defp remote_ranctl_commands(config, files) do
    helper = Path.join(config.current_root, "bin/ran-remote-ranctl")
    request_paths = files.request_paths

    [
      {"precheck", request_paths.precheck},
      {"plan", request_paths.plan},
      {"apply", request_paths.plan},
      {"verify", request_paths.verify},
      {"capture-artifacts", request_paths.verify},
      {"rollback", request_paths.rollback}
    ]
    |> Enum.map(fn {command, request_path} ->
      "RAN_REMOTE_APPLY=1 #{shell_escape(helper)} #{shell_escape(config.target_host)} #{command} #{shell_escape(request_path)}"
    end)
  end

  defp fetch_commands(config, files) do
    helper = Path.join(config.current_root, "bin/ran-fetch-remote-artifacts")

    files.request_paths
    |> Map.values()
    |> Enum.uniq()
    |> Enum.map(fn request_path ->
      "RAN_REMOTE_APPLY=1 #{shell_escape(helper)} #{shell_escape(config.target_host)} #{shell_escape(request_path)}"
    end)
  end

  defp maybe_apply_profile(config) do
    case DeployProfiles.apply_config(config, config.deploy_profile) do
      {:ok, updated} -> updated
      {:error, _payload} -> config
    end
  end

  defp render_profile_manifest(config) do
    summary = render_profile_summary(config)

    %{
      "name" => summary["name"],
      "title" => summary["title"],
      "description" => summary["description"],
      "stability_tier" => summary["stability_tier"],
      "exposure" => summary["exposure"],
      "recommended_for" => summary["recommended_for"],
      "overlays" => summary["overlays"],
      "operator_steps" => summary["operator_steps"],
      "ops_preferences" => summary["ops_preferences"],
      "selected_values" => %{
        "strict_host_probe" => config.strict_host_probe,
        "pull_images" => config.pull_images,
        "dashboard_host" => config.dashboard_host,
        "dashboard_port" => config.dashboard_port,
        "mix_env" => config.mix_env
      },
      "inspiration" => %{
        "source" => "ocudu/srsRAN operational patterns",
        "patterns" => [
          "layered configuration",
          "validator plus autoderive",
          "effective config export",
          "remote control plus metrics surface"
        ]
      }
    }
  end

  defp render_effective_config(config, topology_path, request_path) do
    request_paths = request_bundle_paths(Path.join(config.etc_root, "requests"))

    %{
      "generated_at" => now_iso8601(),
      "deploy_profile" => render_profile_manifest(config),
      "paths" => %{
        "topology_path" => topology_path,
        "request_path" => request_path,
        "request_paths" =>
          Map.new(request_paths, fn {key, path} -> {Atom.to_string(key), path} end),
        "dashboard_env_path" => Path.join(config.etc_root, "ran-dashboard.env"),
        "preflight_env_path" => Path.join(config.etc_root, "ran-host-preflight.env"),
        "readiness_path" => Path.join(config.etc_root, "deploy.readiness.json")
      },
      "topology" => render_topology(config),
      "request" => render_request(config),
      "request_bundle" =>
        render_request_payloads(config)
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end),
      "dashboard_env" => render_dashboard_env_map(config, topology_path),
      "preflight_env" => render_preflight_env_map(config, topology_path, request_path)
    }
  end

  defp remote_request_paths(config, files) do
    files.request_paths
    |> Enum.into(%{}, fn {key, path} ->
      {key, remote_path(config.remote_etc_root, "requests/" <> Path.basename(path))}
    end)
  end

  defp render_profile_summary(config) do
    DeployProfiles.summary(config.deploy_profile)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp render_dashboard_env_map(config, topology_path) do
    %{
      "MIX_ENV" => config.mix_env,
      "RAN_DASHBOARD_HOST" => config.dashboard_host,
      "RAN_DASHBOARD_PORT" => config.dashboard_port,
      "RAN_DEPLOY_PROFILE" => config.deploy_profile,
      "RAN_TOPOLOGY_FILE" => topology_path
    }
  end

  defp render_preflight_env_map(config, topology_path, request_path) do
    %{
      "MIX_ENV" => config.mix_env,
      "RAN_REPO_ROOT" => config.current_root,
      "RAN_DEPLOY_PROFILE" => config.deploy_profile,
      "RAN_TOPOLOGY_FILE" => topology_path,
      "RAN_PREFLIGHT_REQUEST" => request_path
    }
  end

  defp render_env_file(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
    |> Enum.concat([""])
    |> Enum.join("\n")
  end

  defp deployment_readiness(config, files, preflight) do
    profile = DeployProfiles.summary(config.deploy_profile)

    checklist = [
      checklist_item(
        "deploy_profile",
        "Deploy profile selected",
        profile_status(config.deploy_profile),
        profile_detail(profile),
        10
      ),
      checklist_item(
        "bundle_tarball",
        "Bundle tarball resolved",
        bundle_status(config.bundle_tarball),
        bundle_detail(config.bundle_tarball),
        15
      ),
      checklist_item(
        "preview_files",
        "Preview artifacts materialized",
        preview_files_status(files),
        preview_files_detail(files),
        20
      ),
      checklist_item(
        "oai_paths",
        "OAI config paths set",
        oai_paths_status(config),
        oai_paths_detail(config),
        15
      ),
      checklist_item(
        "target_host",
        "Remote target selected",
        target_host_status(config.target_host),
        target_host_detail(config.target_host),
        10
      ),
      checklist_item(
        "remote_layout",
        "Remote install layout defined",
        remote_layout_status(config),
        remote_layout_detail(config),
        10
      ),
      checklist_item(
        "preflight",
        "Host preflight gate",
        preflight_status(preflight),
        preflight_detail(preflight),
        20
      )
    ]

    blockers =
      checklist
      |> Enum.filter(&(&1.status == "failed"))
      |> Enum.map(&Map.take(&1, [:id, :label, :detail]))

    warnings =
      checklist
      |> Enum.filter(&(&1.status == "pending"))
      |> Enum.map(&Map.take(&1, [:id, :label, :detail]))
      |> Kernel.++(posture_warnings(config, profile))

    {status, recommendation} = readiness_status(checklist)

    %{
      generated_at: now_iso8601(),
      status: status,
      score: readiness_score(checklist),
      recommendation: recommendation,
      summary: readiness_summary(status, recommendation, profile, blockers, warnings),
      checklist: checklist,
      blockers: blockers,
      warnings: warnings,
      posture: %{
        strict_host_probe: config.strict_host_probe,
        pull_images: config.pull_images,
        dashboard_host: config.dashboard_host,
        dashboard_port: config.dashboard_port,
        remote_fetchback: get_in(profile, [:ops_preferences, :remote_fetchback]),
        evidence_capture: get_in(profile, [:ops_preferences, :evidence_capture]),
        dashboard_surface: get_in(profile, [:ops_preferences, :dashboard_surface]),
        stability_tier: profile[:stability_tier],
        exposure: profile[:exposure]
      },
      profile: render_profile_summary(config)
    }
  end

  defp checklist_item(id, label, status, detail, weight) do
    %{id: id, label: label, status: status, detail: detail, weight: weight}
  end

  defp profile_status(profile_name) do
    case DeployProfiles.profile(profile_name) do
      {:ok, _profile} -> "passed"
      {:error, _payload} -> "failed"
    end
  end

  defp profile_detail(%{title: title, stability_tier: stability_tier}) do
    "#{title} profile selected with #{stability_tier} stability posture."
  end

  defp bundle_status(nil), do: "pending"
  defp bundle_status(""), do: "pending"

  defp bundle_status(bundle_tarball),
    do: if(File.exists?(bundle_tarball), do: "passed", else: "failed")

  defp bundle_detail(nil), do: "No bundle tarball resolved yet."
  defp bundle_detail(""), do: "No bundle tarball resolved yet."

  defp bundle_detail(bundle_tarball) do
    if File.exists?(bundle_tarball) do
      "Bundle tarball is present at #{bundle_tarball}."
    else
      "Configured bundle tarball is missing: #{bundle_tarball}."
    end
  end

  defp preview_files_status(files) do
    if Enum.all?(preview_file_paths(files), &File.exists?/1), do: "passed", else: "failed"
  end

  defp preview_files_detail(files) do
    if preview_files_status(files) == "passed" do
      "All preview artifacts, manifests, and env files are materialized."
    else
      "One or more preview artifacts could not be written."
    end
  end

  defp preview_file_paths(files) do
    files
    |> Map.values()
    |> Enum.flat_map(fn
      %{} = nested -> Map.values(nested)
      value -> [value]
    end)
    |> Enum.filter(&is_binary/1)
  end

  defp oai_paths_status(config) do
    paths = [config.du_conf_path, config.cucp_conf_path, config.cuup_conf_path]
    if Enum.all?(paths, &(not blank?(&1))), do: "passed", else: "failed"
  end

  defp oai_paths_detail(config) do
    "DU=#{config.du_conf_path}, CUCP=#{config.cucp_conf_path}, CUUP=#{config.cuup_conf_path}."
  end

  defp target_host_status(target_host), do: if(blank?(target_host), do: "pending", else: "passed")

  defp target_host_detail(target_host) do
    if blank?(target_host) do
      "Target host is not set, so handoff commands remain preview-only."
    else
      "Target host #{target_host} is configured for remote handoff."
    end
  end

  defp remote_layout_status(config) do
    cond do
      blank?(config.target_host) ->
        "pending"

      Enum.all?(
        [
          config.remote_bundle_dir,
          config.remote_install_root,
          config.remote_etc_root,
          config.remote_systemd_dir
        ],
        &(not blank?(&1))
      ) ->
        "passed"

      true ->
        "failed"
    end
  end

  defp remote_layout_detail(config) do
    if blank?(config.target_host) do
      "Remote install paths will be enforced after a target host is selected."
    else
      "bundle=#{config.remote_bundle_dir}, install=#{config.remote_install_root}, etc=#{config.remote_etc_root}, systemd=#{config.remote_systemd_dir}."
    end
  end

  defp preflight_status(nil), do: "pending"
  defp preflight_status(%{status: "ok"}), do: "passed"
  defp preflight_status(%{status: "failed"}), do: "failed"
  defp preflight_status(_payload), do: "pending"

  defp preflight_detail(nil), do: "Host preflight has not been run for this preview yet."
  defp preflight_detail(%{status: "ok"}), do: "Host preflight passed."
  defp preflight_detail(%{status: "failed", output: output}), do: short_output_detail(output)
  defp preflight_detail(%{status: status}), do: "Host preflight returned #{status}."

  defp posture_warnings(config, profile) do
    []
    |> maybe_add_warning(
      not config.strict_host_probe,
      "strict_host_probe",
      "Strict probe gate disabled",
      "Apply would proceed without the native host gate. This is not recommended for stable operations."
    )
    |> maybe_add_warning(
      config.pull_images,
      "pull_images",
      "Image pulls enabled",
      "Remote apply may become less deterministic because images can change underneath the rollout."
    )
    |> maybe_add_warning(
      config.dashboard_host == "0.0.0.0" and profile[:exposure] == "ssh_tunnel_first",
      "dashboard_exposure",
      "Dashboard exposure widened",
      "The selected profile expects SSH tunnel access first, but dashboard_host is bound to 0.0.0.0."
    )
  end

  defp maybe_add_warning(warnings, false, _id, _label, _detail), do: warnings

  defp maybe_add_warning(warnings, true, id, label, detail) do
    warnings ++ [%{id: id, label: label, detail: detail}]
  end

  defp readiness_status(checklist) do
    failed_ids =
      checklist
      |> Enum.filter(&(&1.status == "failed"))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    pending_ids =
      checklist
      |> Enum.filter(&(&1.status == "pending"))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    cond do
      MapSet.size(failed_ids) > 0 ->
        {"blocked", "fix_blockers"}

      MapSet.member?(pending_ids, "bundle_tarball") ->
        {"preview_ready", "package_bundle"}

      MapSet.member?(pending_ids, "target_host") ->
        {"preview_ready", "set_target_host"}

      MapSet.member?(pending_ids, "preflight") ->
        {"ready_for_preflight", "run_preflight"}

      true ->
        {"ready_for_remote", "ship_bundle"}
    end
  end

  defp readiness_score(checklist) do
    passed_weight =
      checklist
      |> Enum.filter(&(&1.status == "passed"))
      |> Enum.map(& &1.weight)
      |> Enum.sum()

    total_weight =
      checklist
      |> Enum.map(& &1.weight)
      |> Enum.sum()

    if total_weight == 0 do
      0
    else
      round(passed_weight / total_weight * 100)
    end
  end

  defp readiness_summary(status, recommendation, profile, blockers, warnings) do
    title = profile[:title] || "Deploy"

    base =
      case status do
        "blocked" ->
          "#{title} is blocked until #{length(blockers)} blocker(s) are resolved."

        "preview_ready" ->
          "#{title} is staged locally but still needs handoff inputs before remote apply."

        "ready_for_preflight" ->
          "#{title} is staged for the target host. Run preflight to clear the final gate."

        "ready_for_remote" ->
          "#{title} is ready for remote handoff and host-side ranctl."

        _ ->
          "#{title} staging is in progress."
      end

    advisory =
      case recommendation do
        "fix_blockers" -> " Resolve blocker evidence before continuing."
        "package_bundle" -> " Package or select a bundle tarball."
        "set_target_host" -> " Set the remote host details to unlock handoff commands."
        "run_preflight" -> " Execute preflight before shipping the bundle."
        "ship_bundle" -> " Ship the bundle and begin with remote precheck."
        _ -> ""
      end

    warning_suffix =
      if warnings == [] do
        ""
      else
        " #{length(warnings)} warning(s) should still be reviewed."
      end

    base <> advisory <> warning_suffix
  end

  defp short_output_detail(output) do
    output
    |> to_string()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.first()
    |> case do
      nil -> "Host preflight failed."
      line -> "Host preflight failed: #{line}"
    end
  end

  defp bundled_installer_path(nil), do: nil

  defp bundled_installer_path(bundle_tarball) do
    bundle_tarball
    |> Path.dirname()
    |> Path.join("install_bundle.sh")
  end

  defp ssh_target(config) do
    if blank?(config.ssh_user) do
      config.target_host
    else
      "#{config.ssh_user}@#{config.target_host}"
    end
  end

  defp remote_path(root, suffix) when suffix in [nil, ""], do: root
  defp remote_path(root, suffix), do: Path.join(root, suffix)

  defp maybe_basename(nil), do: nil
  defp maybe_basename(path), do: Path.basename(path)

  defp shell_escape(nil), do: "''"

  defp shell_escape(value) do
    escaped = value |> to_string() |> String.replace("'", "'\"'\"'")
    "'#{escaped}'"
  end

  defp infer_preflight_status(_output, code) when code != 0, do: "failed"

  defp infer_preflight_status(output, 0) do
    case decode_embedded_json(output) do
      {:ok, %{"status" => "ok"}} -> "ok"
      {:ok, %{"status" => "passed"}} -> "ok"
      {:ok, %{"status" => "failed"}} -> "failed"
      {:ok, %{"status" => status}} when is_binary(status) -> status
      _ -> "ok"
    end
  end

  defp maybe_attach_preflight_response(payload, output) do
    case decode_embedded_json(output) do
      {:ok, response} -> Map.put(payload, :response, response)
      {:error, _reason} -> payload
    end
  end

  defp decode_embedded_json(output) do
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

  defp decode_profile_name(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, %{"name" => name}} -> name
      _ -> "unknown"
    end
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp blank?(value), do: value in [nil, ""]
end
