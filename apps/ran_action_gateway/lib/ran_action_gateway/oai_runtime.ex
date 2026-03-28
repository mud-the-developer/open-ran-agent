defmodule RanActionGateway.OaiRuntime do
  @moduledoc """
  Runtime bridge for deterministic OAI DU orchestration through generated Docker Compose assets.
  """

  alias RanActionGateway.{CommandRunner, Store}

  @default_runtime %{
    "mode" => "docker_compose_rfsim_f1",
    "project_name_prefix" => "ran-oai-du",
    "gnb_image" => "oaisoftwarealliance/oai-gnb:develop",
    "cuup_image" => "oaisoftwarealliance/oai-nr-cuup:develop",
    "ue_image" => "oaisoftwarealliance/oai-nr-ue:develop",
    "pull_images" => true,
    "core_subnet" => "192.168.71.0/24",
    "f1c_subnet" => "10.213.72.0/24",
    "f1u_subnet" => "10.213.73.0/24",
    "e1_subnet" => "10.213.77.0/24",
    "ue_subnet" => "10.213.78.0/24",
    "cucp_core_ip" => "192.168.71.150",
    "cuup_core_ip" => "192.168.71.161",
    "cucp_f1c_ip" => "10.213.72.2",
    "du_f1c_ip" => "10.213.72.3",
    "cuup_f1u_ip" => "10.213.73.2",
    "du_f1u_ip" => "10.213.73.3",
    "cucp_e1_ip" => "10.213.77.2",
    "cuup_e1_ip" => "10.213.77.3",
    "du_ue_ip" => "10.213.78.2",
    "ue_ip" => "10.213.78.5",
    "ue_bandwidth_prb" => 106,
    "ue_numerology" => 1,
    "ue_center_frequency_hz" => 3_619_200_000,
    "du_service_name" => "oai-du",
    "cucp_service_name" => "oai-cucp",
    "cuup_service_name" => "oai-cuup",
    "ue_service_name" => "oai-nr-ue"
  }

  @log_tail_lines "10000"
  @observe_log_tail_lines "2000"
  @observe_metric_specs [
    %{
      role: "du",
      id: "du_frame_slot_count",
      label: "DU Frame.Slot tokens",
      pattern: ~r/Frame\.Slot/,
      source_pattern: "Frame.Slot",
      meaning: "Counts DU MAC slot-loop tokens in the current Docker log tail."
    },
    %{
      role: "du",
      id: "du_f1_setup_response_count",
      label: "DU F1 setup responses",
      pattern: ~r/received F1 Setup Response/,
      source_pattern: "received F1 Setup Response",
      meaning: "Counts DU log tokens confirming the CU-CP F1 setup response reached the DU."
    },
    %{
      role: "du",
      id: "du_rfsim_wait_count",
      label: "DU RFsim wait tokens",
      pattern: ~r/Running as server waiting opposite rfsimulators to connect/,
      source_pattern: "Running as server waiting opposite rfsimulators to connect",
      meaning: "Counts DU log tokens showing the RFsim server loop is waiting for the peer side."
    },
    %{
      role: "cucp",
      id: "cucp_f1_setup_response_count",
      label: "CU-CP F1 setup responses",
      pattern: ~r/sending F1 Setup Response/,
      source_pattern: "sending F1 Setup Response",
      meaning: "Counts CU-CP log tokens proving the split control plane answered the DU F1 setup."
    },
    %{
      role: "cuup",
      id: "cuup_e1_established_count",
      label: "CU-UP E1 established tokens",
      pattern: ~r/E1 connection established/,
      source_pattern: "E1 connection established",
      meaning: "Counts CU-UP log tokens confirming E1 association with the CU-CP."
    },
    %{
      role: "ue",
      id: "ue_start_count",
      label: "UE startup tokens",
      pattern: ~r/Starting NR UE soft modem/,
      source_pattern: "Starting NR UE soft modem",
      meaning:
        "Counts UE log tokens confirming the repo-local UE process entered softmodem startup."
    },
    %{
      role: "ue",
      id: "ue_tun_configured_count",
      label: "UE tunnel configured tokens",
      pattern: ~r/Interface oaitun_ue1 successfully configured/,
      source_pattern: "Interface oaitun_ue1 successfully configured",
      meaning: "Counts UE log tokens confirming the UE tunnel device was configured."
    }
  ]

  @type spec_map :: map()

  @spec runtime_requested?(map()) :: boolean()
  def runtime_requested?(metadata) when is_map(metadata) do
    is_map(Map.get(metadata, "oai_runtime")) or is_map(Map.get(metadata, :oai_runtime))
  end

  def runtime_requested?(_metadata), do: false

  @spec resolve(String.t() | nil, map()) :: {:ok, spec_map()} | {:error, map()}
  def resolve(cell_group_id, metadata) do
    metadata_runtime =
      metadata
      |> Map.get("oai_runtime", Map.get(metadata, :oai_runtime, %{}))
      |> normalize_map_keys()

    cell_group_runtime =
      case cell_group_id do
        nil ->
          %{}

        _ ->
          with {:ok, cell_group} <- RanConfig.find_cell_group(cell_group_id) do
            cell_group
            |> Map.get(:oai_runtime, Map.get(cell_group, "oai_runtime", %{}))
            |> normalize_map_keys()
          else
            _ -> %{}
          end
      end

    env_defaults =
      Application.get_env(:ran_action_gateway, :oai_runtime_defaults, %{})
      |> normalize_map_keys()

    spec =
      @default_runtime
      |> Map.merge(env_defaults)
      |> Map.merge(cell_group_runtime)
      |> Map.merge(metadata_runtime)
      |> put_project_name(cell_group_id)
      |> put_service_names()
      |> put_container_names()

    validate_spec(spec)
  end

  @spec precheck(String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def precheck(cell_group_id, metadata) do
    with {:ok, spec} <- resolve(cell_group_id, metadata) do
      checks =
        [
          check("docker_available", docker_available?()),
          check("docker_daemon_reachable", docker_daemon_reachable?()),
          check("repo_root_present", File.dir?(spec["repo_root"])),
          check("du_conf_present", File.exists?(spec["du_conf_path"])),
          check("cucp_conf_present", File.exists?(spec["cucp_conf_path"])),
          check("cuup_conf_present", File.exists?(spec["cuup_conf_path"])),
          check("gnb_image_present", image_present?(spec["gnb_image"])),
          check(
            "cuup_image_present_or_pull_enabled",
            image_present?(spec["cuup_image"]) or spec["pull_images"]
          )
        ] ++ optional_ue_precheck_checks(spec) ++ conf_checks(spec)

      failed? = Enum.any?(checks, &(&1["status"] == "failed"))

      {:ok,
       %{
         status: if(failed?, do: "failed", else: "ok"),
         runtime_mode: runtime_mode(spec),
         runtime_spec: public_spec(spec),
         checks: checks
       }}
    end
  end

  @spec plan(String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def plan(change_id, cell_group_id, metadata) do
    with {:ok, spec} <- resolve(cell_group_id, metadata),
         {:ok, runtime_spec} <- materialize_runtime_spec(change_id, spec) do
      compose_path = Store.runtime_compose_path(change_id)
      compose_body = render_compose(runtime_spec)

      path =
        compose_path
        |> Path.dirname()
        |> File.mkdir_p!()
        |> then(fn _ -> File.write!(compose_path, compose_body) end)
        |> then(fn _ -> compose_path end)

      {:ok,
       %{
         runtime_mode: runtime_mode(runtime_spec),
         compose_path: path,
         project_name: runtime_spec["project_name"],
         services: runtime_services(runtime_spec),
         containers: runtime_containers(runtime_spec),
         images: runtime_images(runtime_spec),
         runtime_spec: public_spec(runtime_spec)
       }}
    end
  end

  @spec apply(String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def apply(change_id, cell_group_id, metadata) do
    with {:ok, plan} <- plan(change_id, cell_group_id, metadata),
         {:ok, spec} <- resolve(cell_group_id, metadata),
         :ok <- maybe_pull_images(spec),
         {output, 0} <- compose(plan.compose_path, spec["project_name"], ["up", "-d"]) do
      {:ok,
       %{
         runtime_mode: runtime_mode(spec),
         compose_path: plan.compose_path,
         project_name: spec["project_name"],
         services: plan.services,
         containers: plan.containers,
         output: output
       }}
    else
      {:error, _} = error ->
        error

      {output, exit_code} ->
        {:error,
         %{
           status: "runtime_apply_failed",
           runtime_mode: "docker_compose_rfsim_f1",
           errors: ["docker compose up failed with exit code #{exit_code}"],
           output: output
         }}
    end
  end

  @spec verify(String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def verify(change_id, cell_group_id, metadata) do
    with {:ok, spec} <- resolve(cell_group_id, metadata),
         {:ok, statuses} <- inspect_runtime(spec),
         :ok <- write_logs(change_id, spec),
         true <- Enum.all?(statuses, & &1["running"]) do
      log_checks = runtime_log_checks(change_id, spec)

      {:ok,
       %{
         runtime_mode: runtime_mode(spec),
         project_name: spec["project_name"],
         compose_path: Store.runtime_compose_path(change_id),
         logs: Enum.map(runtime_containers(spec), &Store.runtime_log_path(change_id, &1)),
         containers: statuses,
         checks: log_checks
       }}
    else
      {:error, _} = error ->
        error

      false ->
        {:error,
         %{
           status: "runtime_verify_failed",
           runtime_mode: "docker_compose_rfsim_f1",
           errors: ["one or more OAI runtime containers are not running"]
         }}
    end
  end

  @spec rollback(String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def rollback(change_id, cell_group_id, metadata) do
    with {:ok, spec} <- resolve(cell_group_id, metadata),
         compose_path <- Store.runtime_compose_path(change_id),
         true <- File.exists?(compose_path),
         {output, 0} <-
           compose(compose_path, spec["project_name"], ["down", "-v", "--remove-orphans"]) do
      {:ok,
       %{
         runtime_mode: runtime_mode(spec),
         project_name: spec["project_name"],
         compose_path: compose_path,
         output: output
       }}
    else
      {:error, _} = error ->
        error

      false ->
        {:error,
         %{
           status: "runtime_missing_plan",
           errors: ["compose artifact not found for #{change_id}"]
         }}

      {output, exit_code} ->
        {:error,
         %{
           status: "runtime_rollback_failed",
           errors: ["docker compose down failed with exit code #{exit_code}"],
           output: output
         }}
    end
  end

  @spec observe(String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def observe(cell_group_id, metadata) do
    with {:ok, spec} <- resolve(cell_group_id, metadata),
         {:ok, statuses} <- inspect_runtime(spec),
         {:ok, observed_containers} <- enrich_observed_containers(spec, statuses) do
      token_metrics = Enum.flat_map(observed_containers, &Map.get(&1, "token_metrics", []))

      {:ok,
       %{
         lane_id: "oai_split_rfsim_repo_local_v1",
         runtime_mode: runtime_mode(spec),
         project_name: spec["project_name"],
         runtime_state: observed_runtime_state(observed_containers),
         service_count: length(observed_containers),
         running_service_count: Enum.count(observed_containers, & &1["running"]),
         healthy_service_count: Enum.count(observed_containers, &(&1["health"] == "healthy")),
         containers: observed_containers,
         token_metrics: token_metrics
       }}
    end
  end

  @spec capture_artifacts(String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def capture_artifacts(change_id, cell_group_id, metadata) do
    with {:ok, spec} <- resolve(cell_group_id, metadata),
         :ok <- write_logs(change_id, spec) do
      {:ok,
       %{
         runtime_mode: runtime_mode(spec),
         compose_path: Store.runtime_compose_path(change_id),
         logs: Enum.map(runtime_containers(spec), &Store.runtime_log_path(change_id, &1))
       }}
    end
  end

  @spec contract_snapshot(String.t() | nil, map()) :: {:ok, map()} | {:error, map()}
  def contract_snapshot(cell_group_id, metadata) do
    with {:ok, spec} <- resolve(cell_group_id, metadata) do
      public_spec = public_spec(spec)

      {:ok,
       %{
         runtime_mode: runtime_mode(spec),
         runtime_digest: runtime_digest(public_spec)
       }}
    end
  end

  defp validate_spec(spec) do
    required_fields = [
      "repo_root",
      "du_conf_path",
      "cucp_conf_path",
      "cuup_conf_path",
      "gnb_image",
      "cuup_image"
    ]

    missing =
      Enum.filter(required_fields, fn field ->
        spec[field] in [nil, ""]
      end)

    case missing do
      [] ->
        {:ok, spec}

      _ ->
        {:error,
         %{
           status: "invalid_runtime_spec",
           errors: Enum.map(missing, &"#{&1} is required for OAI runtime orchestration")
         }}
    end
  end

  defp put_project_name(spec, cell_group_id) do
    suffix =
      spec["project_name"] ||
        [spec["project_name_prefix"], cell_group_id || "adhoc"]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("-")
        |> String.replace(~r/[^a-zA-Z0-9_.-]+/, "-")
        |> String.downcase()

    Map.put(spec, "project_name", suffix)
  end

  defp put_service_names(spec) do
    spec
    |> Map.put_new("du_service_name", "oai-du")
    |> Map.put_new("cucp_service_name", "oai-cucp")
    |> Map.put_new("cuup_service_name", "oai-cuup")
    |> Map.put_new("ue_service_name", "oai-nr-ue")
  end

  defp put_container_names(spec) do
    project_name = spec["project_name"]

    spec
    |> Map.put("du_container_name", "#{project_name}-du")
    |> Map.put("cucp_container_name", "#{project_name}-cucp")
    |> Map.put("cuup_container_name", "#{project_name}-cuup")
    |> maybe_put_ue_container_name(project_name)
  end

  defp maybe_put_ue_container_name(spec, project_name) do
    if ue_requested?(spec) do
      Map.put(spec, "ue_container_name", "#{project_name}-nr-ue")
    else
      spec
    end
  end

  defp public_spec(spec) do
    spec
    |> Map.take([
      "mode",
      "repo_root",
      "du_conf_path",
      "cucp_conf_path",
      "cuup_conf_path",
      "ue_conf_path",
      "rendered_du_conf_path",
      "rendered_cucp_conf_path",
      "rendered_cuup_conf_path",
      "gnb_image",
      "cuup_image",
      "ue_image",
      "project_name",
      "du_container_name",
      "cucp_container_name",
      "cuup_container_name",
      "ue_container_name",
      "pull_images",
      "core_subnet",
      "f1c_subnet",
      "f1u_subnet",
      "e1_subnet",
      "ue_subnet",
      "cucp_core_ip",
      "cuup_core_ip",
      "cucp_f1c_ip",
      "du_f1c_ip",
      "cuup_f1u_ip",
      "du_f1u_ip",
      "cucp_e1_ip",
      "cuup_e1_ip",
      "du_ue_ip",
      "ue_ip",
      "ue_bandwidth_prb",
      "ue_numerology",
      "ue_center_frequency_hz"
    ])
    |> Map.update("mode", nil, &maybe_to_string/1)
  end

  defp runtime_containers(spec) do
    containers = [
      spec["cucp_container_name"],
      spec["cuup_container_name"],
      spec["du_container_name"]
    ]

    if ue_requested?(spec) do
      containers ++ [spec["ue_container_name"]]
    else
      containers
    end
  end

  defp runtime_services(spec) do
    services = [
      spec["cucp_service_name"],
      spec["cuup_service_name"],
      spec["du_service_name"]
    ]

    if ue_requested?(spec) do
      services ++ [spec["ue_service_name"]]
    else
      services
    end
  end

  defp runtime_images(spec) do
    images = %{
      gnb: spec["gnb_image"],
      cuup: spec["cuup_image"]
    }

    if ue_requested?(spec) do
      Map.put(images, :ue, spec["ue_image"])
    else
      images
    end
  end

  defp optional_ue_precheck_checks(spec) do
    if ue_requested?(spec) do
      [
        check("ue_conf_present", File.exists?(spec["ue_conf_path"])),
        check(
          "ue_image_present_or_pull_enabled",
          image_present?(spec["ue_image"]) or spec["pull_images"]
        ),
        check("ue_tun_device_present", File.exists?("/dev/net/tun"))
      ]
    else
      []
    end
  end

  defp conf_checks(spec) do
    [
      check(
        "du_conf_declares_f1_transport",
        body_matches?(spec["du_conf_path"], ~r/tr_n_preference\s*=\s*"f1"/)
      ),
      check(
        "du_conf_declares_rfsimulator",
        body_matches?(spec["du_conf_path"], ~r/rfsimulator\s*=\s*\(/)
      ),
      check(
        "cucp_conf_declares_f1_split",
        body_matches?(spec["cucp_conf_path"], ~r/tr_s_preference\s*=\s*"f1"/)
      ),
      check(
        "cuup_conf_declares_cuup_identity",
        body_matches?(spec["cuup_conf_path"], ~r/gNB_CU_UP_ID\s*=\s*/)
      ),
      check(
        "du_conf_patch_points_present",
        conf_keys_present?(spec["du_conf_path"], ["local_n_address", "remote_n_address"])
      ),
      check(
        "cucp_conf_patch_points_present",
        conf_keys_present?(spec["cucp_conf_path"], [
          "local_s_address",
          "ipv4_cucp",
          "GNB_IPV4_ADDRESS_FOR_NG_AMF"
        ])
      ),
      check(
        "cuup_conf_patch_points_present",
        conf_keys_present?(spec["cuup_conf_path"], [
          "local_s_address",
          "remote_s_address",
          "ipv4_cucp",
          "ipv4_cuup",
          "GNB_IPV4_ADDRESS_FOR_NG_AMF",
          "GNB_IPV4_ADDRESS_FOR_NGU"
        ])
      )
    ] ++ optional_ue_conf_checks(spec)
  end

  defp optional_ue_conf_checks(spec) do
    if ue_requested?(spec) do
      [
        check("ue_conf_declares_uicc", body_matches?(spec["ue_conf_path"], ~r/\buicc0\b/)),
        check(
          "ue_conf_declares_pdu_session",
          body_matches?(spec["ue_conf_path"], ~r/\bpdu_sessions\b/)
        ),
        check(
          "ue_conf_declares_rfsimulator",
          body_matches?(spec["ue_conf_path"], ~r/\brfsimulator\b/)
        )
      ]
    else
      []
    end
  end

  defp runtime_log_checks(change_id, spec) do
    du_log_path = Store.runtime_log_path(change_id, spec["du_container_name"])
    cucp_log_path = Store.runtime_log_path(change_id, spec["cucp_container_name"])
    cuup_log_path = Store.runtime_log_path(change_id, spec["cuup_container_name"])

    du_slot_activity? = log_contains?(du_log_path, ~r/Frame\.Slot/)
    cucp_f1_response? = log_contains?(cucp_log_path, ~r/sending F1 Setup Response/)

    [
      check(
        "du_log_f1_setup_complete",
        log_contains?(du_log_path, ~r/received F1 Setup Response/) or
          (du_slot_activity? and cucp_f1_response?)
      ),
      check(
        "du_log_main_loop_ready",
        log_contains?(du_log_path, ~r/TYPE <CTRL-C> TO TERMINATE/) or
          log_contains?(
            du_log_path,
            ~r/Running as server waiting opposite rfsimulators to connect/
          ) or
          du_slot_activity?
      ),
      check(
        "cucp_log_f1_setup_response_sent",
        cucp_f1_response?
      ),
      check(
        "cuup_log_e1_established",
        log_contains?(cuup_log_path, ~r/E1 connection established/)
      )
    ] ++ optional_ue_log_checks(change_id, spec)
  end

  defp optional_ue_log_checks(change_id, spec) do
    if ue_requested?(spec) do
      ue_log_path = Store.runtime_log_path(change_id, spec["ue_container_name"])

      [
        check("ue_log_started", log_contains?(ue_log_path, ~r/Starting NR UE soft modem/)),
        check(
          "ue_log_tun_configured",
          log_contains?(ue_log_path, ~r/Interface oaitun_ue1 successfully configured/)
        )
      ]
    else
      []
    end
  end

  defp materialize_runtime_spec(change_id, spec) do
    with {:ok, rendered} <- render_conf_overlays(change_id, spec) do
      {:ok,
       spec
       |> Map.put("rendered_du_conf_path", rendered.du)
       |> Map.put("rendered_cucp_conf_path", rendered.cucp)
       |> Map.put("rendered_cuup_conf_path", rendered.cuup)}
    end
  end

  defp render_conf_overlays(change_id, spec) do
    conf_dir = Store.runtime_conf_dir(change_id)
    File.mkdir_p!(conf_dir)

    du_path = Store.runtime_conf_path(change_id, "du")
    cucp_path = Store.runtime_conf_path(change_id, "cucp")
    cuup_path = Store.runtime_conf_path(change_id, "cuup")

    with {:ok, du_body} <- File.read(spec["du_conf_path"]),
         {:ok, patched_du} <- patch_du_conf(du_body, spec),
         :ok <- File.write(du_path, patched_du),
         {:ok, cucp_body} <- File.read(spec["cucp_conf_path"]),
         {:ok, patched_cucp} <- patch_cucp_conf(cucp_body, spec),
         :ok <- File.write(cucp_path, patched_cucp),
         {:ok, cuup_body} <- File.read(spec["cuup_conf_path"]),
         {:ok, patched_cuup} <- patch_cuup_conf(cuup_body, spec),
         :ok <- File.write(cuup_path, patched_cuup) do
      {:ok, %{du: du_path, cucp: cucp_path, cuup: cuup_path}}
    else
      {:error, %{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         %{
           status: "runtime_conf_overlay_write_failed",
           errors: [inspect(reason)]
         }}
    end
  end

  defp patch_du_conf(body, spec) do
    with {:ok, body} <- replace_conf_value(body, "local_n_address", spec["du_f1c_ip"], :du),
         {:ok, body} <- replace_conf_value(body, "remote_n_address", "oai-cucp", :du) do
      {:ok, body}
    end
  end

  defp patch_cucp_conf(body, spec) do
    with {:ok, body} <- replace_conf_value(body, "local_s_address", spec["cucp_f1c_ip"], :cucp),
         {:ok, body} <- replace_conf_value(body, "ipv4_cucp", spec["cucp_e1_ip"], :cucp),
         {:ok, body} <-
           replace_conf_value(
             body,
             "GNB_IPV4_ADDRESS_FOR_NG_AMF",
             "#{spec["cucp_core_ip"]}/24",
             :cucp
           ) do
      {:ok, body}
    end
  end

  defp patch_cuup_conf(body, spec) do
    with {:ok, body} <- replace_conf_value(body, "local_s_address", spec["cuup_f1u_ip"], :cuup),
         {:ok, body} <- replace_conf_value(body, "remote_s_address", "127.0.0.1", :cuup),
         {:ok, body} <- replace_conf_value(body, "ipv4_cucp", spec["cucp_e1_ip"], :cuup),
         {:ok, body} <- replace_conf_value(body, "ipv4_cuup", spec["cuup_e1_ip"], :cuup),
         {:ok, body} <-
           replace_conf_value(
             body,
             "GNB_IPV4_ADDRESS_FOR_NG_AMF",
             "#{spec["cuup_core_ip"]}/24",
             :cuup
           ),
         {:ok, body} <-
           replace_conf_value(
             body,
             "GNB_IPV4_ADDRESS_FOR_NGU",
             "#{spec["cuup_core_ip"]}/24",
             :cuup
           ) do
      {:ok, body}
    end
  end

  defp render_compose(spec) do
    """
    services:
      oai-cucp:
        image: #{spec["gnb_image"]}
        container_name: #{spec["cucp_container_name"]}
        hostname: oai-cucp
        cap_drop:
          - ALL
        extra_hosts:
          - "oai-amf:127.0.0.1"
        environment:
          USE_ADDITIONAL_OPTIONS: --log_config.global_log_options level,nocolor,time --gNBs.[0].E1_INTERFACE.[0].ipv4_cucp #{spec["cucp_e1_ip"]} --gNBs.[0].local_s_address #{spec["cucp_f1c_ip"]}
          ASAN_OPTIONS: detect_leaks=0
        networks:
          core_net:
            ipv4_address: #{spec["cucp_core_ip"]}
            aliases:
              - oai-cucp
          f1c_net:
            ipv4_address: #{spec["cucp_f1c_ip"]}
            aliases:
              - oai-cucp
          e1_net:
            ipv4_address: #{spec["cucp_e1_ip"]}
            aliases:
              - oai-cucp
        volumes:
          - "#{mounted_conf_path(spec, "cucp")}:/opt/oai-gnb/etc/gnb.conf:ro"
        healthcheck:
          test: /bin/bash -c "pgrep nr-softmodem"
          start_period: 10s
          start_interval: 500ms
          interval: 10s
          timeout: 5s
          retries: 5

      oai-cuup:
        image: #{spec["cuup_image"]}
        container_name: #{spec["cuup_container_name"]}
        hostname: oai-cuup
        cap_drop:
          - ALL
        extra_hosts:
          - "oai-amf:127.0.0.1"
        depends_on:
          - oai-cucp
        environment:
          USE_ADDITIONAL_OPTIONS: --log_config.global_log_options level,nocolor,time --gNBs.[0].E1_INTERFACE.[0].ipv4_cucp #{spec["cucp_e1_ip"]} --gNBs.[0].E1_INTERFACE.[0].ipv4_cuup #{spec["cuup_e1_ip"]} --gNBs.[0].local_s_address #{spec["cuup_f1u_ip"]} --gNBs.[0].remote_s_address 127.0.0.1
          ASAN_OPTIONS: detect_leaks=0
        networks:
          core_net:
            ipv4_address: #{spec["cuup_core_ip"]}
            aliases:
              - oai-cuup
          f1u_net:
            ipv4_address: #{spec["cuup_f1u_ip"]}
            aliases:
              - oai-cuup
          e1_net:
            ipv4_address: #{spec["cuup_e1_ip"]}
            aliases:
              - oai-cuup
        volumes:
          - "#{mounted_conf_path(spec, "cuup")}:/opt/oai-gnb/etc/gnb.conf:ro"
        healthcheck:
          test: /bin/bash -c "pgrep nr-cuup"
          start_period: 10s
          start_interval: 500ms
          interval: 10s
          timeout: 5s
          retries: 5

      oai-du:
        image: #{spec["gnb_image"]}
        container_name: #{spec["du_container_name"]}
        hostname: oai-du
        cap_drop:
          - ALL
        depends_on:
          - oai-cucp
          - oai-cuup
        environment:
          USE_ADDITIONAL_OPTIONS: --rfsim --log_config.global_log_options level,nocolor,time --MACRLCs.[0].local_n_address #{spec["du_f1c_ip"]} --MACRLCs.[0].remote_n_address #{spec["cucp_f1c_ip"]} --MACRLCs.[0].local_n_address_f1u #{spec["du_f1u_ip"]}
          ASAN_OPTIONS: detect_leaks=0
        networks:
          f1c_net:
            ipv4_address: #{spec["du_f1c_ip"]}
            aliases:
              - oai-du
          f1u_net:
            ipv4_address: #{spec["du_f1u_ip"]}
            aliases:
              - oai-du
          ue_net:
            ipv4_address: #{spec["du_ue_ip"]}
            aliases:
              - oai-du
        volumes:
          - "#{mounted_conf_path(spec, "du")}:/opt/oai-gnb/etc/gnb.conf:ro"
        healthcheck:
          test: /bin/bash -c "pgrep nr-softmodem"
          start_period: 10s
          start_interval: 500ms
          interval: 10s
          timeout: 5s
          retries: 5

    #{render_optional_ue_service(spec)}
    networks:
      core_net:
        driver: bridge
        ipam:
          config:
            - subnet: #{spec["core_subnet"]}
      f1c_net:
        driver: bridge
        ipam:
          config:
            - subnet: #{spec["f1c_subnet"]}
      f1u_net:
        driver: bridge
        ipam:
          config:
            - subnet: #{spec["f1u_subnet"]}
      e1_net:
        driver: bridge
        ipam:
          config:
            - subnet: #{spec["e1_subnet"]}
      ue_net:
        driver: bridge
        ipam:
          config:
            - subnet: #{spec["ue_subnet"]}
    """
  end

  defp render_optional_ue_service(spec) do
    if ue_requested?(spec) do
      [
        "  oai-nr-ue:",
        "    image: #{spec["ue_image"]}",
        "    container_name: #{spec["ue_container_name"]}",
        "    cap_drop:",
        "      - ALL",
        "    cap_add:",
        "      - NET_ADMIN",
        "      - NET_RAW",
        "    depends_on:",
        "      - oai-du",
        "    environment:",
        "      USE_ADDITIONAL_OPTIONS: --rfsim --log_config.global_log_options level,nocolor,time -r #{spec["ue_bandwidth_prb"]} --numerology #{spec["ue_numerology"]} -C #{spec["ue_center_frequency_hz"]} --rfsimulator.[0].serveraddr #{spec["du_service_name"]}",
        "      ASAN_OPTIONS: detect_leaks=0",
        "    networks:",
        "      ue_net:",
        "        ipv4_address: #{spec["ue_ip"]}",
        "    devices:",
        "      - /dev/net/tun:/dev/net/tun",
        "    volumes:",
        "      - \"#{mounted_conf_path(spec, "ue")}:/opt/oai-nr-ue/etc/nr-ue.conf:ro\"",
        "    healthcheck:",
        "      test: /bin/bash -c \"pgrep nr-uesoftmodem\"",
        "      start_period: 10s",
        "      start_interval: 500ms",
        "      interval: 10s",
        "      timeout: 5s",
        "      retries: 5",
        ""
      ]
      |> Enum.join("\n")
    else
      ""
    end
  end

  defp docker_available? do
    match?({_output, 0}, CommandRunner.run("docker", ["--version"]))
  end

  defp docker_daemon_reachable? do
    match?({_output, 0}, CommandRunner.run("docker", ["info"]))
  end

  defp image_present?(image) do
    match?({_output, 0}, CommandRunner.run("docker", ["image", "inspect", image]))
  end

  defp maybe_pull_images(spec) do
    images =
      spec
      |> runtime_images()
      |> Map.values()
      |> Enum.uniq()

    Enum.reduce_while(images, :ok, fn image, :ok ->
      cond do
        image_present?(image) ->
          {:cont, :ok}

        spec["pull_images"] ->
          case CommandRunner.run("docker", ["pull", image], into: "") do
            {_output, 0} -> {:cont, :ok}
            {output, exit_code} -> {:halt, {:error, pull_error(image, output, exit_code)}}
          end

        true ->
          {:halt,
           {:error,
            %{
              status: "runtime_image_missing",
              errors: ["missing docker image #{image} and pull_images=false"]
            }}}
      end
    end)
  end

  defp compose(compose_path, project_name, extra_args) do
    CommandRunner.run("docker", ["compose", "-p", project_name, "-f", compose_path] ++ extra_args,
      into: ""
    )
  end

  defp inspect_runtime(spec) do
    statuses =
      Enum.map(runtime_containers(spec), fn container_name ->
        case CommandRunner.run("docker", ["inspect", container_name], into: "") do
          {output, 0} ->
            with {:ok, [payload | _]} <- JSON.decode(output) do
              state = payload["State"] || %{}

              {:ok,
               %{
                 "name" => container_name,
                 "running" => state["Running"] || false,
                 "status" => state["Status"],
                 "health" => get_in(state, ["Health", "Status"])
               }}
            else
              {:error, reason} ->
                {:error,
                 %{
                   status: "runtime_inspect_decode_failed",
                   errors: [inspect(reason)],
                   container: container_name
                 }}
            end

          {output, exit_code} ->
            {:error,
             %{
               status: "runtime_inspect_failed",
               errors: ["docker inspect failed with exit code #{exit_code}"],
               container: container_name,
               output: output
             }}
        end
      end)

    case Enum.find(statuses, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error

      nil ->
        {:ok, Enum.map(statuses, fn {:ok, payload} -> payload end)}
    end
  end

  defp enrich_observed_containers(spec, statuses) when is_list(statuses) do
    roles = runtime_container_roles(spec)

    observed =
      Enum.map(statuses, fn status ->
        container_name = status["name"]
        role_info = Map.get(roles, container_name, %{})
        role = role_info["role"]

        case CommandRunner.run(
               "docker",
               ["logs", "--tail", @observe_log_tail_lines, container_name],
               into: ""
             ) do
          {output, 0} ->
            token_metrics = token_metrics_for_container(container_name, role, output)

            {:ok,
             status
             |> Map.put("role", role)
             |> Map.put("service_name", role_info["service_name"])
             |> Map.put("log_probe_status", "ok")
             |> Map.put("log_tail_line_count", log_line_count(output))
             |> Map.put("token_counts", token_count_map(token_metrics))
             |> Map.put("token_metrics", token_metrics)}

          {output, exit_code} ->
            {:ok,
             status
             |> Map.put("role", role)
             |> Map.put("service_name", role_info["service_name"])
             |> Map.put("log_probe_status", "error")
             |> Map.put("log_tail_line_count", 0)
             |> Map.put("log_error", "docker logs failed with exit code #{exit_code}")
             |> Map.put("log_error_output", output)
             |> Map.put("token_counts", %{})
             |> Map.put("token_metrics", [])}
        end
      end)

    {:ok, Enum.map(observed, fn {:ok, payload} -> payload end)}
  end

  defp runtime_container_roles(spec) do
    %{
      spec["du_container_name"] => %{
        "role" => "du",
        "service_name" => spec["du_service_name"]
      },
      spec["cucp_container_name"] => %{
        "role" => "cucp",
        "service_name" => spec["cucp_service_name"]
      },
      spec["cuup_container_name"] => %{
        "role" => "cuup",
        "service_name" => spec["cuup_service_name"]
      }
    }
    |> maybe_put_ue_container_role(spec)
  end

  defp maybe_put_ue_container_role(roles, spec) do
    if ue_requested?(spec) do
      Map.put(roles, spec["ue_container_name"], %{
        "role" => "ue",
        "service_name" => spec["ue_service_name"]
      })
    else
      roles
    end
  end

  defp token_metrics_for_container(container_name, role, output) when is_binary(role) do
    @observe_metric_specs
    |> Enum.filter(&(&1.role == role))
    |> Enum.map(fn spec ->
      %{
        "id" => spec.id,
        "label" => spec.label,
        "count" => count_matches(output, spec.pattern),
        "role" => role,
        "container_name" => container_name,
        "source_kind" => "docker_logs_tail",
        "source_pattern" => spec.source_pattern,
        "source_tail_lines" => String.to_integer(@observe_log_tail_lines),
        "meaning" => spec.meaning
      }
    end)
  end

  defp token_metrics_for_container(_container_name, _role, _output), do: []

  defp token_count_map(metrics) do
    Map.new(metrics, fn metric -> {metric["id"], metric["count"]} end)
  end

  defp count_matches(body, regex) do
    regex
    |> Regex.scan(body)
    |> length()
  end

  defp log_line_count(body) do
    body
    |> String.split("\n", trim: true)
    |> length()
  end

  defp observed_runtime_state(containers) when is_list(containers) and containers != [] do
    cond do
      Enum.all?(containers, &(&1["running"] and &1["health"] == "healthy")) ->
        "running"

      Enum.any?(containers, &(!&1["running"] or &1["log_probe_status"] == "error")) ->
        "degraded"

      true ->
        "warming"
    end
  end

  defp observed_runtime_state(_containers), do: "unavailable"

  defp write_logs(change_id, spec) do
    Enum.reduce_while(runtime_containers(spec), :ok, fn container_name, :ok ->
      case CommandRunner.run("docker", ["logs", "--tail", @log_tail_lines, container_name],
             into: ""
           ) do
        {output, 0} ->
          path = Store.runtime_log_path(change_id, container_name)
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, output)
          {:cont, :ok}

        {output, exit_code} ->
          {:halt,
           {:error,
            %{
              status: "runtime_log_capture_failed",
              errors: ["docker logs failed with exit code #{exit_code}"],
              container: container_name,
              output: output
            }}}
      end
    end)
  end

  defp pull_error(image, output, exit_code) do
    %{
      status: "runtime_image_pull_failed",
      image: image,
      errors: ["docker pull failed with exit code #{exit_code}"],
      output: output
    }
  end

  defp normalize_map_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_map_keys(_), do: %{}

  defp replace_conf_value(body, key, value, role) do
    regex = ~r/(#{Regex.escape(key)}\s*=\s*")([^"]*)(")/

    if Regex.match?(regex, body) do
      {:ok,
       Regex.replace(regex, body, fn _full, prefix, _existing, suffix ->
         prefix <> value <> suffix
       end)}
    else
      {:error,
       %{
         status: "runtime_conf_patch_failed",
         role: Atom.to_string(role),
         key: key,
         errors: ["#{Atom.to_string(role)} conf missing patchable key #{key}"]
       }}
    end
  end

  defp mounted_conf_path(spec, role) do
    spec
    |> Map.get("rendered_#{role}_conf_path")
    |> Kernel.||(Map.fetch!(spec, "#{role}_conf_path"))
    |> Path.expand()
  end

  defp ue_requested?(spec), do: spec["ue_conf_path"] not in [nil, ""]

  defp conf_keys_present?(path, keys) do
    case File.read(path) do
      {:ok, body} ->
        Enum.all?(keys, fn key ->
          Regex.match?(~r/\b#{Regex.escape(key)}\s*=\s*"/, body)
        end)

      _ ->
        false
    end
  end

  defp body_matches?(path, regex) do
    case File.read(path) do
      {:ok, body} -> Regex.match?(regex, body)
      _ -> false
    end
  end

  defp log_contains?(path, regex) do
    case File.read(path) do
      {:ok, body} -> Regex.match?(regex, body)
      _ -> false
    end
  end

  defp check(name, true), do: %{"name" => name, "status" => "passed"}
  defp check(name, false), do: %{"name" => name, "status" => "failed"}

  defp runtime_mode(spec), do: maybe_to_string(spec["mode"])

  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value), do: value

  defp runtime_digest(spec) do
    spec
    |> canonicalize()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), canonicalize(nested)} end)
    |> Enum.sort()
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value), do: value
end
