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
    "du_service_name" => "oai-du",
    "cucp_service_name" => "oai-cucp",
    "cuup_service_name" => "oai-cuup"
  }

  @services ~w(oai-cucp oai-cuup oai-du)
  @log_tail_lines "10000"

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
        ] ++ conf_checks(spec)

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
         services: @services,
         containers: runtime_containers(runtime_spec),
         images: %{
           gnb: runtime_spec["gnb_image"],
           cuup: runtime_spec["cuup_image"]
         },
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
         {:ok, statuses} <- inspect_runtime(spec) do
      {:ok,
       %{
         runtime_mode: runtime_mode(spec),
         project_name: spec["project_name"],
         containers: statuses
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
  end

  defp put_container_names(spec) do
    project_name = spec["project_name"]

    spec
    |> Map.put("du_container_name", "#{project_name}-du")
    |> Map.put("cucp_container_name", "#{project_name}-cucp")
    |> Map.put("cuup_container_name", "#{project_name}-cuup")
  end

  defp public_spec(spec) do
    spec
    |> Map.take([
      "mode",
      "repo_root",
      "du_conf_path",
      "cucp_conf_path",
      "cuup_conf_path",
      "rendered_du_conf_path",
      "rendered_cucp_conf_path",
      "rendered_cuup_conf_path",
      "gnb_image",
      "cuup_image",
      "project_name",
      "du_container_name",
      "cucp_container_name",
      "cuup_container_name",
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
      "du_ue_ip"
    ])
    |> Map.update("mode", nil, &maybe_to_string/1)
  end

  defp runtime_containers(spec) do
    [
      spec["cucp_container_name"],
      spec["cuup_container_name"],
      spec["du_container_name"]
    ]
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
    ]
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
    ]
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
          f1c_net:
            ipv4_address: #{spec["cucp_f1c_ip"]}
          e1_net:
            ipv4_address: #{spec["cucp_e1_ip"]}
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
          f1u_net:
            ipv4_address: #{spec["cuup_f1u_ip"]}
          e1_net:
            ipv4_address: #{spec["cuup_e1_ip"]}
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
        cap_drop:
          - ALL
        depends_on:
          - oai-cucp
          - oai-cuup
        environment:
          USE_ADDITIONAL_OPTIONS: --rfsim --log_config.global_log_options level,nocolor,time --MACRLCs.[0].local_n_address #{spec["du_f1c_ip"]} --MACRLCs.[0].remote_n_address oai-cucp --MACRLCs.[0].local_n_address_f1u #{spec["du_f1u_ip"]}
          ASAN_OPTIONS: detect_leaks=0
        networks:
          f1c_net:
            ipv4_address: #{spec["du_f1c_ip"]}
          f1u_net:
            ipv4_address: #{spec["du_f1u_ip"]}
          ue_net:
            ipv4_address: #{spec["du_ue_ip"]}
        volumes:
          - "#{mounted_conf_path(spec, "du")}:/opt/oai-gnb/etc/gnb.conf:ro"
        healthcheck:
          test: /bin/bash -c "pgrep nr-softmodem"
          start_period: 10s
          start_interval: 500ms
          interval: 10s
          timeout: 5s
          retries: 5

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
      [spec["gnb_image"], spec["cuup_image"]]
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
  end

  defp put_container_names(spec) do
    project_name = spec["project_name"]

    spec
    |> Map.put("du_container_name", "#{project_name}-du")
    |> Map.put("cucp_container_name", "#{project_name}-cucp")
    |> Map.put("cuup_container_name", "#{project_name}-cuup")
  end

  defp public_spec(spec) do
    spec
    |> Map.take([
      "mode",
      "repo_root",
      "du_conf_path",
      "cucp_conf_path",
      "cuup_conf_path",
      "rendered_du_conf_path",
      "rendered_cucp_conf_path",
      "rendered_cuup_conf_path",
      "gnb_image",
      "cuup_image",
      "project_name",
      "du_container_name",
      "cucp_container_name",
      "cuup_container_name",
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
      "du_ue_ip"
    ])
    |> Map.update("mode", nil, &maybe_to_string/1)
  end

  defp runtime_containers(spec) do
    [
      spec["cucp_container_name"],
      spec["cuup_container_name"],
      spec["du_container_name"]
    ]
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
    ]
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
    ]
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
          f1c_net:
            ipv4_address: #{spec["cucp_f1c_ip"]}
          e1_net:
            ipv4_address: #{spec["cucp_e1_ip"]}
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
          f1u_net:
            ipv4_address: #{spec["cuup_f1u_ip"]}
          e1_net:
            ipv4_address: #{spec["cuup_e1_ip"]}
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
        cap_drop:
          - ALL
        depends_on:
          - oai-cucp
          - oai-cuup
        environment:
          USE_ADDITIONAL_OPTIONS: --rfsim --log_config.global_log_options level,nocolor,time --MACRLCs.[0].local_n_address #{spec["du_f1c_ip"]} --MACRLCs.[0].remote_n_address oai-cucp --MACRLCs.[0].local_n_address_f1u #{spec["du_f1u_ip"]}
          ASAN_OPTIONS: detect_leaks=0
        networks:
          f1c_net:
            ipv4_address: #{spec["du_f1c_ip"]}
          f1u_net:
            ipv4_address: #{spec["du_f1u_ip"]}
          ue_net:
            ipv4_address: #{spec["du_ue_ip"]}
        volumes:
          - "#{mounted_conf_path(spec, "du")}:/opt/oai-gnb/etc/gnb.conf:ro"
        healthcheck:
          test: /bin/bash -c "pgrep nr-softmodem"
          start_period: 10s
          start_interval: 500ms
          interval: 10s
          timeout: 5s
          retries: 5

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
      [spec["gnb_image"], spec["cuup_image"]]
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
