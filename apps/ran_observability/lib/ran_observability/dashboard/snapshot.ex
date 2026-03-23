defmodule RanObservability.Dashboard.Snapshot do
  @moduledoc """
  Builds a unified snapshot of local RAN state, runtime evidence, and agent control surface.
  """

  alias RanObservability.CommandRunner
  alias RanObservability.Dashboard.DeployRunner

  @artifact_kinds ~w(plans changes verify captures approvals rollback_plans probe_snapshots)
  @retention_policy %{
    json_keep: 20,
    runtime_keep: 8,
    release_keep: 5
  }

  @spec build(keyword()) :: map()
  def build(opts \\ []) do
    artifact_root = Keyword.get(opts, :artifact_root, RanObservability.artifact_root())
    skills_root = Keyword.get(opts, :skills_root, "ops/skills")
    command_runner = Keyword.get(opts, :command_runner, CommandRunner)
    recent_bundles = recent_release_bundles(artifact_root, 6)
    recent_changes = recent_activity(artifact_root, 12)
    native_contract_runs = recent_native_contract_runs(recent_changes, 8)
    remote_runs = recent_remote_runs(artifact_root, 6)
    install_runs = recent_install_runs(artifact_root, 8)
    retention = retention_snapshot(artifact_root)
    debug = debug_snapshot(recent_changes, remote_runs, install_runs)

    containers = list_containers(command_runner)
    ran_containers = Enum.filter(containers, &(&1.domain == "ran"))
    agent_containers = Enum.filter(containers, &(&1.domain == "agent"))

    %{
      generated_at: now_iso8601(),
      identity: %{
        title: "RAN Mission Control",
        subtitle: "Runtime, agents, changes, and evidence in one surface",
        host: Application.get_env(:ran_observability, :dashboard_host, "127.0.0.1"),
        port: Application.get_env(:ran_observability, :dashboard_port, 4050)
      },
      overview: %{
        ran_runtime_count: length(ran_containers),
        agent_runtime_count: length(agent_containers),
        healthy_runtime_count: Enum.count(containers, &health_ok?/1),
        recent_change_count: length(recent_changes),
        native_contract_count: length(native_contract_runs),
        recent_bundle_count: length(recent_bundles),
        remote_run_count: length(remote_runs),
        install_run_count: length(install_runs),
        debug_failure_count: debug.recent_failure_count,
        prune_candidate_count: retention.summary.prune_count
      },
      ran: %{
        profile: RanConfig.current_profile() |> to_string(),
        topology_source: RanConfig.topology_source(),
        validation: sanitize_validation(RanConfig.validation_report()),
        supported_backends: Enum.map(RanCore.supported_backends(), &Atom.to_string/1),
        cell_groups: Enum.map(RanConfig.cell_groups(), &format_cell_group(&1, artifact_root))
      },
      release: %{
        readiness: sanitize_release_readiness(RanConfig.release_readiness()),
        recent_bundles: recent_bundles
      },
      deploy:
        DeployRunner.defaults_payload()
        |> Map.merge(%{
          recent_remote_runs: remote_runs,
          recent_remote_run_count: length(remote_runs),
          recent_install_runs: install_runs,
          recent_install_run_count: length(install_runs),
          latest_debug_incident: debug.latest_failure,
          recent_debug_failures: debug.recent_failures,
          recent_debug_failure_count: debug.recent_failure_count
        }),
      debug: debug,
      retention: retention,
      runtime: %{
        status: if(containers == [], do: "unavailable", else: "ok"),
        containers: containers,
        ran_containers: ran_containers,
        agent_containers: agent_containers,
        native_contracts: native_contract_runs,
        evidence: recent_logs(artifact_root, 6)
      },
      agents: %{
        skills: list_skills(skills_root),
        lanes: [
          %{name: "intent", summary: "operators and skills issue ranctl actions"},
          %{name: "plan", summary: "changes become plan/apply/verify/rollback artifacts"},
          %{name: "runtime", summary: "OAI, DU split, FlexRIC, and emulators report live state"},
          %{name: "evidence", summary: "logs and captures remain attached to each change"}
        ]
      },
      activity: %{
        recent_changes: recent_changes,
        native_contract_runs: native_contract_runs,
        remote_runs: remote_runs,
        install_runs: install_runs,
        artifact_root: Path.expand(artifact_root)
      }
    }
  end

  defp format_cell_group(cell_group, artifact_root) do
    id = fetch_value(cell_group, :id)

    %{
      id: id,
      du: fetch_value(cell_group, :du),
      backend: fetch_value(cell_group, :backend) |> to_string_value(),
      failover_targets:
        cell_group
        |> fetch_value(:failover_targets, [])
        |> Enum.map(&to_string_value/1),
      scheduler: fetch_value(cell_group, :scheduler) |> to_string_value(),
      runtime_mode:
        cell_group
        |> fetch_value(:oai_runtime, %{})
        |> fetch_value(:mode)
        |> to_string_value(),
      control_state: load_control_state(artifact_root, id)
    }
  end

  defp sanitize_validation(report) do
    %{
      profile: report.profile |> to_string_value(),
      status: report.status |> to_string_value(),
      cell_group_count: report.cell_group_count,
      default_backend: report.default_backend |> to_string_value(),
      scheduler_adapter: report.scheduler_adapter |> to_string_value(),
      supported_backends: Enum.map(report.supported_backends || [], &to_string_value/1),
      supported_schedulers: Enum.map(report.supported_schedulers || [], &to_string_value/1),
      topology_source: report.topology_source,
      errors: report.errors || []
    }
  end

  defp sanitize_release_readiness(report) do
    %{
      status: report.status |> to_string_value(),
      release_unit: report.release_unit |> to_string_value(),
      profile: report.profile |> to_string_value(),
      default_backend: report.default_backend |> to_string_value(),
      scheduler_adapter: report.scheduler_adapter |> to_string_value(),
      cell_group_count: report.cell_group_count,
      topology_source: report.topology_source,
      checks: report.checks || [],
      errors: report.errors || []
    }
  end

  defp retention_snapshot(artifact_root) do
    json_prune =
      @artifact_kinds
      |> Enum.flat_map(
        &retention_entries(artifact_root, &1, "*.json", @retention_policy.json_keep)
      )

    runtime_prune =
      retention_entries(artifact_root, "runtime", "*", @retention_policy.runtime_keep)

    release_prune =
      retention_entries(artifact_root, "releases", "*", @retention_policy.release_keep)

    protected = protected_entries(artifact_root, "control_state")

    prune_candidates = json_prune ++ runtime_prune ++ release_prune

    %{
      policy: @retention_policy,
      summary: %{
        prune_count: length(prune_candidates),
        protected_count: length(protected)
      },
      prune_candidates: Enum.take(prune_candidates, 6),
      protected: Enum.take(protected, 6)
    }
  end

  defp retention_entries(artifact_root, category, pattern, keep_limit) do
    [artifact_root, category, pattern]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.filter(&(File.regular?(&1) or File.dir?(&1)))
    |> Enum.map(fn path ->
      %{
        category: category,
        path: Path.expand(path),
        updated_at: path_updated_at(path)
      }
    end)
    |> Enum.sort_by(& &1.updated_at, :desc)
    |> Enum.drop(keep_limit)
    |> Enum.map(fn entry -> Map.update!(entry, :updated_at, &DateTime.to_iso8601/1) end)
  end

  defp protected_entries(artifact_root, category) do
    [artifact_root, category, "*"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.map(fn path ->
      %{
        category: category,
        path: Path.expand(path),
        updated_at: path |> path_updated_at() |> DateTime.to_iso8601()
      }
    end)
  end

  defp list_containers(command_runner) do
    case command_runner.run("docker", ["ps", "-a", "--format", "{{json .}}"], []) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&decode_container/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&container_rank/1)

      _ ->
        []
    end
  end

  defp decode_container(line) do
    with {:ok, payload} <- JSON.decode(line) do
      name = payload["Names"] || "unknown"

      %{
        name: name,
        image: payload["Image"],
        state: payload["State"],
        status: payload["Status"],
        running_for: payload["RunningFor"],
        networks: split_csv(payload["Networks"]),
        ports: blank_to_nil(payload["Ports"]),
        compose_project: label_value(payload["Labels"], "com.docker.compose.project"),
        compose_service: label_value(payload["Labels"], "com.docker.compose.service"),
        domain: classify_container(name, payload["Image"]),
        tone: tone_from_status(payload["Status"])
      }
    else
      _ -> nil
    end
  end

  defp list_skills(skills_root) do
    skills_root
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(fn skill_dir ->
      references =
        skill_dir
        |> Path.join("references/*")
        |> Path.wildcard()

      scripts =
        skill_dir
        |> Path.join("scripts/*")
        |> Path.wildcard()

      %{
        name: Path.basename(skill_dir),
        skill_path: Path.expand(Path.join(skill_dir, "SKILL.md")),
        reference_count: length(references),
        script_count: length(scripts),
        has_run_script: File.exists?(Path.join(skill_dir, "scripts/run.sh"))
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp recent_activity(artifact_root, limit) do
    artifact_root
    |> list_artifact_files()
    |> Enum.map(&decode_artifact/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at_unix, :desc)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :updated_at_unix))
  end

  defp list_artifact_files(artifact_root) do
    Enum.flat_map(@artifact_kinds, fn kind ->
      Path.wildcard(Path.join([artifact_root, kind, "*.json"]))
    end)
  end

  defp decode_artifact(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- JSON.decode(body),
         {:ok, stat} <- File.stat(path) do
      updated_at = stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
      native_contract = decode_native_contract(payload)

      %{
        id: payload["change_id"] || payload["incident_id"] || Path.basename(path, ".json"),
        command: payload["command"],
        status: payload["status"],
        scope: payload["scope"],
        summary: payload["summary"],
        path: Path.expand(path),
        phase: path |> Path.dirname() |> Path.basename(),
        updated_at: updated_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        updated_at_unix: DateTime.to_unix(updated_at),
        target_backend: payload["target_backend"],
        next: payload["next"] || [],
        artifacts: payload["artifacts"] || [],
        approval_ref: payload["approval_ref"],
        rollback_plan_ref: payload["rollback_plan_ref"],
        source_plan: payload["source_plan"],
        restored_from: payload["restored_from"],
        native_contract: native_contract
      }
    else
      _ -> nil
    end
  end

  defp recent_native_contract_runs(recent_changes, limit) do
    recent_changes
    |> Enum.filter(&(&1.native_contract && map_size(&1.native_contract) > 0))
    |> Enum.map(&native_contract_run_summary/1)
    |> Enum.take(limit)
  end

  defp native_contract_run_summary(change) do
    contract = change.native_contract || %{}

    %{
      id: change.id,
      command: change.command,
      status: change.status,
      phase: change.phase,
      path: change.path,
      updated_at: change.updated_at,
      target_backend: change.target_backend,
      native_contract: contract,
      backend_family: fetch_value(contract, :backend_family),
      worker_kind: fetch_value(contract, :worker_kind),
      transport_worker: fetch_value(contract, :transport_worker),
      execution_lane: fetch_value(contract, :execution_lane),
      dispatch_mode: fetch_value(contract, :dispatch_mode),
      transport_mode: fetch_value(contract, :transport_mode),
      policy_mode: fetch_value(contract, :policy_mode),
      accepted_profile: fetch_value(contract, :accepted_profile),
      fronthaul_session: fetch_value(contract, :fronthaul_session),
      device_session_ref: fetch_value(contract, :device_session_ref),
      device_session_state: fetch_value(contract, :device_session_state),
      device_generation: fetch_value(contract, :device_generation),
      device_profile: fetch_value(contract, :device_profile),
      policy_surface_ref: fetch_value(contract, :policy_surface_ref),
      handshake_ref: fetch_value(contract, :handshake_ref),
      handshake_state: fetch_value(contract, :handshake_state),
      handshake_attempts: fetch_value(contract, :handshake_attempts),
      last_handshake_at: fetch_value(contract, :last_handshake_at),
      strict_host_probe: fetch_value(contract, :strict_host_probe),
      activation_gate: fetch_value(contract, :activation_gate),
      handshake_target: fetch_value(contract, :handshake_target),
      probe_evidence_ref: fetch_value(contract, :probe_evidence_ref),
      probe_checked_at: fetch_value(contract, :probe_checked_at),
      probe_required_resources: fetch_value(contract, :probe_required_resources),
      probe_observations: fetch_value(contract, :probe_observations),
      host_probe_ref: fetch_value(contract, :host_probe_ref),
      host_probe_status: fetch_value(contract, :host_probe_status),
      host_probe_mode: fetch_value(contract, :host_probe_mode),
      host_probe_failures: fetch_value(contract, :host_probe_failures),
      session_epoch: fetch_value(contract, :session_epoch),
      session_started_at: fetch_value(contract, :session_started_at),
      last_submit_at: fetch_value(contract, :last_submit_at),
      last_uplink_at: fetch_value(contract, :last_uplink_at),
      last_resume_at: fetch_value(contract, :last_resume_at),
      drain_state: fetch_value(contract, :drain_state),
      drain_reason: fetch_value(contract, :drain_reason),
      queue_depth: fetch_value(contract, :queue_depth),
      deadline_miss_count: fetch_value(contract, :deadline_miss_count),
      timing_window_us: fetch_value(contract, :timing_window_us),
      timing_budget_us: fetch_value(contract, :timing_budget_us),
      health_status: contract |> fetch_value(:health, %{}) |> fetch_value(:status),
      health_checks: contract |> fetch_value(:health, %{}) |> fetch_value(:checks, []),
      source: fetch_value(contract, :source),
      source_path: fetch_value(contract, :source_path)
    }
  end

  defp decode_native_contract(payload) when is_map(payload) do
    payload
    |> native_contract_candidates("payload", 2)
    |> Enum.reduce(%{}, fn {source, map}, acc ->
      case native_contract_summary(map, source) do
        nil -> acc
        summary -> merge_contract_summary(acc, summary)
      end
    end)
    |> case do
      %{} = contract when map_size(contract) == 0 -> nil
      contract -> contract
    end
  end

  defp decode_native_contract(_payload), do: nil

  defp native_contract_candidates(map, source, depth) when is_map(map) and depth >= 0 do
    direct = [{source, map}]

    nested =
      Enum.flat_map([:native_contract, :contract_state, :runtime_result, :runtime], fn key ->
        case fetch_value(map, key, %{}) do
          nested_map when is_map(nested_map) and map_size(nested_map) > 0 ->
            native_contract_candidates(nested_map, "#{source}.#{key}", depth - 1)

          _ ->
            []
        end
      end)

    direct ++ nested
  end

  defp native_contract_candidates(_map, _source, _depth), do: []

  defp native_contract_summary(map, source) when is_map(map) do
    timing_fields = native_contract_timing_fields(map)

    details = %{
      backend_family: contract_field(map, :backend_family),
      worker_kind: contract_field(map, :worker_kind),
      transport_worker: contract_field(map, :transport_worker),
      execution_lane: contract_field(map, :execution_lane),
      transport_mode: contract_field(map, :transport_mode),
      dispatch_mode: contract_field(map, :dispatch_mode),
      policy_mode: contract_field(map, :policy_mode),
      accepted_profile: contract_field(map, :accepted_profile),
      fronthaul_session: contract_field(map, :fronthaul_session),
      device_session_ref: contract_field(map, :device_session_ref),
      device_session_state: contract_field(map, :device_session_state),
      device_generation: contract_field(map, :device_generation),
      device_profile: contract_field(map, :device_profile),
      policy_surface_ref: contract_field(map, :policy_surface_ref),
      handshake_ref: contract_field(map, :handshake_ref),
      handshake_state: contract_field(map, :handshake_state),
      handshake_attempts: contract_field(map, :handshake_attempts),
      last_handshake_at: contract_field(map, :last_handshake_at),
      strict_host_probe: contract_field(map, :strict_host_probe),
      activation_gate: contract_field(map, :activation_gate),
      handshake_target: contract_field(map, :handshake_target),
      probe_evidence_ref: contract_field(map, :probe_evidence_ref),
      probe_checked_at: contract_field(map, :probe_checked_at),
      probe_required_resources: contract_field(map, :probe_required_resources),
      probe_observations: contract_field(map, :probe_observations),
      host_probe_ref: contract_field(map, :host_probe_ref),
      host_probe_status: contract_field(map, :host_probe_status),
      host_probe_mode: contract_field(map, :host_probe_mode),
      host_probe_failures: contract_field(map, :host_probe_failures),
      worker_state: contract_field(map, :worker_state),
      session_state: contract_field(map, :session_state),
      transport_state: contract_field(map, :transport_state),
      dispatch_state: contract_field(map, :dispatch_state),
      session_epoch: fetch_value(timing_fields, :session_epoch),
      session_started_at: fetch_value(timing_fields, :session_started_at),
      last_submit_at: fetch_value(timing_fields, :last_submit_at),
      last_uplink_at: fetch_value(timing_fields, :last_uplink_at),
      last_resume_at: fetch_value(timing_fields, :last_resume_at),
      drain_state: fetch_value(timing_fields, :drain_state),
      drain_reason: fetch_value(timing_fields, :drain_reason),
      queue_depth: fetch_value(timing_fields, :queue_depth),
      deadline_miss_count: fetch_value(timing_fields, :deadline_miss_count),
      timing_window_us: fetch_value(timing_fields, :timing_window_us),
      timing_budget_us: fetch_value(timing_fields, :timing_budget_us),
      health: native_contract_health(map),
      signals: native_contract_signals(map)
    }

    details =
      details
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == %{} or value == [] end)
      |> Enum.into(%{})

    if map_size(details) == 0 do
      nil
    else
      Map.merge(%{source: source, source_path: source}, details)
    end
  end

  defp native_contract_summary(_map, _source), do: nil

  defp native_contract_timing_fields(map) when is_map(map) do
    session = native_contract_section(map, :session)
    session_source = if map_size(session) > 0, do: session, else: map

    drain =
      native_contract_section(session_source, :drain)
      |> case do
        %{} = nested when map_size(nested) > 0 -> nested
        _ -> native_contract_section(map, :drain)
      end

    queue =
      native_contract_section(session_source, :queue)
      |> case do
        %{} = nested when map_size(nested) > 0 -> nested
        _ -> native_contract_section(map, :queue)
      end

    timing =
      native_contract_section(session_source, :timing)
      |> case do
        %{} = nested when map_size(nested) > 0 -> nested
        _ -> native_contract_section(map, :timing)
      end

    %{
      session_epoch:
        contract_field_any(session, [:session_epoch, :epoch]) ||
          contract_field_any(map, [:session_epoch, :epoch]),
      session_started_at:
        contract_field_any(session, [:session_started_at, :started_at]) ||
          contract_field_any(map, [:session_started_at, :started_at]),
      last_submit_at:
        contract_field_any(session, [:last_submit_at]) ||
          contract_field_any(map, [:last_submit_at]),
      last_uplink_at:
        contract_field_any(session, [:last_uplink_at]) ||
          contract_field_any(map, [:last_uplink_at]),
      last_resume_at:
        contract_field_any(session, [:last_resume_at]) ||
          contract_field_any(map, [:last_resume_at]),
      drain_state:
        contract_field_any(drain, [:drain_state, :state]) ||
          contract_field_any(map, [:drain_state, :state]),
      drain_reason:
        contract_field_any(drain, [:drain_reason, :reason]) ||
          contract_field_any(map, [:drain_reason, :reason]),
      queue_depth:
        contract_field_any(queue, [:queue_depth, :depth]) ||
          contract_field_any(map, [:queue_depth, :depth]),
      deadline_miss_count:
        contract_field_any(timing, [:deadline_miss_count]) ||
          contract_field_any(map, [:deadline_miss_count]),
      timing_window_us:
        contract_field_any(timing, [:timing_window_us, :window_us]) ||
          contract_field_any(map, [:timing_window_us, :window_us]),
      timing_budget_us:
        contract_field_any(timing, [:timing_budget_us, :budget_us]) ||
          contract_field_any(map, [:timing_budget_us, :budget_us])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp native_contract_timing_fields(_map), do: %{}

  defp native_contract_section(map, key) when is_map(map) do
    case fetch_value(map, key, %{}) do
      nested when is_map(nested) -> nested
      _ -> %{}
    end
  end

  defp native_contract_section(_map, _key), do: %{}

  defp contract_field_any(map, keys) when is_map(map) do
    Enum.find_value(keys, &contract_field(map, &1))
  end

  defp contract_field_any(_map, _keys), do: nil

  defp native_contract_health(map) do
    direct =
      if native_contract_healthish?(map) do
        native_contract_health_fields(map)
      else
        %{}
      end

    nested = fetch_value(map, :health, %{})

    nested =
      if is_map(nested) do
        native_contract_health_fields(nested)
      else
        %{}
      end

    merge_contract_summary(direct, nested)
  end

  defp native_contract_healthish?(map) do
    Enum.any?([:checks, :tone, :state], fn key ->
      case fetch_value(map, key, nil) do
        nil -> false
        [] -> false
        %{} -> false
        _ -> true
      end
    end)
  end

  defp native_contract_signals(map) do
    direct = native_contract_signal_fields(map)
    nested = fetch_value(map, :signals, %{})

    nested =
      if is_map(nested) do
        native_contract_signal_fields(nested)
      else
        %{}
      end

    merge_contract_summary(direct, nested)
  end

  defp native_contract_health_fields(map) do
    %{
      status: contract_field(map, :status),
      state: contract_field(map, :state),
      tone: contract_field(map, :tone),
      checks: contract_field(map, :checks)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
    |> Enum.into(%{})
  end

  defp native_contract_signal_fields(map) do
    %{
      uplink_ring_depth: contract_field(map, :uplink_ring_depth),
      batch_window_us: contract_field(map, :batch_window_us),
      slot_budget_us: contract_field(map, :slot_budget_us),
      last_batch_size: contract_field(map, :last_batch_size),
      last_uplink_kind: contract_field(map, :last_uplink_kind)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp contract_field(map, key) do
    fetch_value(map, key)
  end

  defp merge_contract_summary(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      cond do
        is_map(left_value) and is_map(right_value) ->
          merge_contract_summary(left_value, right_value)

        right_value in [nil, %{}, []] ->
          left_value

        true ->
          right_value
      end
    end)
  end

  defp merge_contract_summary(left, right), do: right || left

  defp recent_logs(artifact_root, limit) do
    artifact_root
    |> Path.join("runtime/**/*.log")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      {:ok, stat} = File.stat(path)
      updated_at = stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

      %{
        name: Path.basename(path),
        path: Path.expand(path),
        updated_at: updated_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        updated_at_unix: DateTime.to_unix(updated_at),
        excerpt: log_excerpt(path)
      }
    end)
    |> Enum.sort_by(& &1.updated_at_unix, :desc)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :updated_at_unix))
  end

  defp recent_release_bundles(artifact_root, limit) do
    artifact_root
    |> Path.join("releases/*/manifest.json")
    |> Path.wildcard()
    |> Enum.map(&decode_release_bundle/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at_unix, :desc)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :updated_at_unix))
  end

  defp decode_release_bundle(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- JSON.decode(body),
         {:ok, stat} <- File.stat(path) do
      updated_at = stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

      %{
        bundle_id: payload["bundle_id"] || Path.basename(Path.dirname(path)),
        status: payload["status"],
        release_unit: payload["release_unit"],
        manifest_path: Path.expand(path),
        tarball_path: payload["tarball_path"],
        profile: payload["profile"],
        topology_source: payload["topology_source"],
        updated_at: updated_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        updated_at_unix: DateTime.to_unix(updated_at)
      }
    else
      _ -> nil
    end
  end

  defp recent_remote_runs(artifact_root, limit) do
    artifact_root
    |> Path.join("remote_runs/*/*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&decode_remote_run/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at_unix, :desc)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :updated_at_unix))
  end

  defp recent_install_runs(artifact_root, limit) do
    quick_install_runs =
      artifact_root
      |> Path.join("deploy_preview/quick_install/*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    ship_runs =
      artifact_root
      |> Path.join("install_runs/*/*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    (quick_install_runs ++ ship_runs)
    |> Enum.map(&decode_install_run/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at_unix, :desc)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :updated_at_unix))
  end

  defp decode_install_run(path) do
    updated_at = path_updated_at(path)
    summary_path = path_if_exists(Path.join(path, "debug-summary.txt"))
    summary = load_key_value_file(summary_path)
    debug_pack_path = path_if_exists(Path.join(path, "debug-pack.txt"))
    guide_path = path_if_exists(Path.join(path, "INSTALL.md"))
    preview_command_path = path_if_exists(Path.join(path, "install.preview.sh"))
    apply_command_path = path_if_exists(Path.join(path, "install.apply.sh"))
    remote_precheck_path = path_if_exists(Path.join(path, "remote.precheck.sh"))
    plan_path = path_if_exists(Path.join(path, "plan.txt"))
    transcript_path = path_if_exists(Path.join(path, "transcript.log"))
    command_log_path = path_if_exists(Path.join(path, "command.log"))
    result_path = path_if_exists(Path.join(path, "result.jsonl"))

    excerpt =
      install_run_excerpt(
        debug_pack_path,
        summary_path,
        guide_path,
        transcript_path,
        command_log_path
      )

    host =
      blank_to_nil(summary["target_host"]) || blank_to_nil(summary["ssh_target"]) ||
        "local-preview"

    label = Path.basename(path)

    %{
      id: "#{host}:#{label}",
      kind: summary["kind"] || infer_install_kind(path),
      host: host,
      label: label,
      status: summary["status"] || summary["readiness_status"] || "unknown",
      path: Path.expand(path),
      summary_path: summary_path,
      debug_pack_path: debug_pack_path,
      guide_path: guide_path,
      plan_path: plan_path,
      transcript_path: transcript_path || command_log_path,
      result_path: result_path,
      preview_command_path: preview_command_path,
      apply_command_path: apply_command_path,
      remote_precheck_path: remote_precheck_path,
      deploy_profile: summary["deploy_profile"],
      readiness_status: summary["readiness_status"],
      readiness_score: parse_integer(summary["readiness_score"]),
      recommendation: summary["recommendation"],
      bundle: summary["bundle"],
      failed_step: blank_to_nil(summary["failed_step"]),
      failed_command: blank_to_nil(summary["failed_command"]),
      exit_code: parse_integer(summary["exit_code"]),
      excerpt: excerpt,
      updated_at: updated_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      updated_at_unix: DateTime.to_unix(updated_at)
    }
  end

  defp decode_remote_run(path) do
    updated_at = path_updated_at(path)
    plan_path = path_if_exists(Path.join(path, "plan.txt"))
    result_path = path_if_exists(Path.join(path, "result.jsonl"))
    debug_summary_path = path_if_exists(Path.join(path, "debug-summary.txt"))
    debug_summary = load_key_value_file(debug_summary_path)
    debug_pack_path = path_if_exists(Path.join(path, "debug-pack.txt"))
    command_log_path = path_if_exists(Path.join(path, "command.log"))
    fetch_plan_path = path_if_exists(Path.join(path, "fetch/plan.txt"))
    fetch_archive_path = path_if_exists(Path.join(path, "fetch/remote-evidence.tar.gz"))
    fetch_extract_path = path_if_exists(Path.join(path, "fetch/extracted"))
    fetch_summary_path = path_if_exists(Path.join(path, "fetch/extracted/fetch-summary.txt"))
    fetch_debug_summary_path = path_if_exists(Path.join(path, "fetch/debug-summary.txt"))
    fetch_debug_summary = load_key_value_file(fetch_debug_summary_path)
    fetch_debug_pack_path = path_if_exists(Path.join(path, "fetch/debug-pack.txt"))
    fetch_summary = load_key_value_file(fetch_summary_path)
    remote_result = load_remote_result(result_path)
    label = Path.basename(path)
    host = path |> Path.dirname() |> Path.basename()
    command = remote_result["command"] || infer_remote_command(label)

    status =
      blank_to_nil(debug_summary["status"]) || remote_result["status"] ||
        remote_run_status(result_path, fetch_extract_path)

    %{
      id: "#{host}:#{label}",
      host: host,
      label: label,
      command: command,
      status: status,
      path: Path.expand(path),
      plan_path: plan_path,
      result_path: result_path,
      command_log_path: command_log_path,
      summary_path: debug_summary_path,
      debug_pack_path: debug_pack_path,
      fetch_plan_path: fetch_plan_path,
      fetch_archive_path: fetch_archive_path,
      fetch_extract_path: fetch_extract_path,
      fetch_summary_path: fetch_summary_path,
      fetch_debug_summary_path: fetch_debug_summary_path,
      fetch_debug_pack_path: fetch_debug_pack_path,
      change_id: fetch_summary["change_id"] || remote_result["change_id"],
      incident_id: fetch_summary["incident_id"] || remote_result["incident_id"],
      cell_group: fetch_summary["cell_group"],
      fetched_entries: parse_integer(fetch_summary["copied_entries"]),
      fetch_status: if(fetch_extract_path, do: "fetched", else: "pending"),
      failed_step:
        blank_to_nil(debug_summary["failed_step"]) ||
          blank_to_nil(fetch_debug_summary["failed_step"]),
      failed_command:
        blank_to_nil(debug_summary["failed_command"]) ||
          blank_to_nil(fetch_debug_summary["failed_command"]),
      exit_code:
        parse_integer(debug_summary["exit_code"]) ||
          parse_integer(fetch_debug_summary["exit_code"]),
      excerpt:
        remote_run_excerpt(
          fetch_debug_pack_path,
          debug_pack_path,
          command_log_path,
          fetch_summary_path,
          result_path,
          plan_path
        ),
      updated_at: updated_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      updated_at_unix: DateTime.to_unix(updated_at)
    }
  end

  defp load_remote_result(nil), do: %{}

  defp load_remote_result(path) do
    path
    |> File.read()
    |> case do
      {:ok, body} -> decode_json_candidates(body)
      _ -> %{}
    end
  end

  defp decode_json_candidates(output) when is_binary(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.find_value(fn candidate ->
      case JSON.decode(candidate) do
        {:ok, payload} -> payload
        {:error, _reason} -> nil
      end
    end)
    |> case do
      nil ->
        case JSON.decode(output) do
          {:ok, payload} when is_map(payload) -> payload
          _ -> %{}
        end

      payload ->
        payload
    end
  end

  defp infer_remote_command(label) do
    case Regex.run(~r/^\d{8}T\d{6}-(.+)$/, label, capture: :all_but_first) do
      [command] -> command
      _ -> label
    end
  end

  defp remote_run_status(result_path, fetch_extract_path) do
    cond do
      fetch_extract_path -> "fetched"
      result_path -> "executed"
      true -> "planned"
    end
  end

  defp remote_run_excerpt(
         fetch_debug_pack_path,
         debug_pack_path,
         command_log_path,
         fetch_summary_path,
         result_path,
         plan_path
       ) do
    [
      fetch_debug_pack_path,
      debug_pack_path,
      command_log_path,
      fetch_summary_path,
      result_path,
      plan_path
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn candidate ->
      case File.read(candidate) do
        {:ok, body} ->
          lines =
            body
            |> String.split("\n", trim: true)
            |> Enum.reject(&(&1 == ""))
            |> Enum.take(-5)

          if lines == [], do: nil, else: lines

        _ ->
          nil
      end
    end) || []
  end

  defp infer_install_kind(path) do
    if String.contains?(Path.expand(path), "/deploy_preview/quick_install/") do
      "quick_install"
    else
      "ship_bundle"
    end
  end

  defp install_run_excerpt(
         debug_pack_path,
         summary_path,
         guide_path,
         transcript_path,
         command_log_path
       ) do
    [debug_pack_path, command_log_path, transcript_path, summary_path, guide_path]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn candidate ->
      case File.read(candidate) do
        {:ok, body} ->
          lines =
            body
            |> String.split("\n", trim: true)
            |> Enum.reject(&(&1 == ""))
            |> Enum.take(-6)

          if lines == [], do: nil, else: lines

        _ ->
          nil
      end
    end) || []
  end

  defp load_key_value_file(nil), do: %{}

  defp load_key_value_file(path) do
    path
    |> File.read()
    |> case do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, "=", parts: 2) do
            [key, value] -> Map.put(acc, key, value)
            _ -> acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp path_if_exists(path) do
    if File.exists?(path), do: Path.expand(path), else: nil
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp debug_snapshot(recent_changes, remote_runs, install_runs) do
    recent_failures =
      (Enum.map(install_runs, &install_debug_incident/1) ++
         Enum.map(remote_runs, &remote_debug_incident/1) ++
         Enum.map(recent_changes, &change_debug_incident/1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(& &1.failure)
      |> Enum.sort_by(& &1.updated_at, :desc)
      |> Enum.take(8)

    %{
      latest_failure: List.first(recent_failures),
      recent_failures: recent_failures,
      recent_failure_count: length(recent_failures)
    }
  end

  defp install_debug_incident(run) do
    status = run.status || run.readiness_status

    if failure_status?(status) do
      %{
        id: run.id,
        kind: run.kind || "install_run",
        status: status,
        host: run.host,
        command: nil,
        deploy_profile: run.deploy_profile,
        failed_step: run.failed_step,
        failed_command: run.failed_command,
        exit_code: run.exit_code,
        path: run.path,
        summary_path: run.summary_path,
        debug_pack_path: run.debug_pack_path,
        plan_path: run.plan_path,
        transcript_path: run.transcript_path,
        result_path: run.result_path,
        updated_at: run.updated_at,
        excerpt: run.excerpt,
        failure: true
      }
    end
  end

  defp remote_debug_incident(run) do
    if failure_status?(run.status) do
      %{
        id: run.id,
        kind: "remote_ranctl",
        status: run.status,
        host: run.host,
        command: run.command,
        deploy_profile: nil,
        failed_step: run.failed_step,
        failed_command: run.failed_command,
        exit_code: run.exit_code,
        path: run.path,
        summary_path: run.summary_path || run.fetch_debug_summary_path,
        debug_pack_path: run.debug_pack_path || run.fetch_debug_pack_path,
        plan_path: run.plan_path,
        transcript_path: run.command_log_path,
        result_path: run.result_path,
        updated_at: run.updated_at,
        excerpt: run.excerpt,
        failure: true
      }
    end
  end

  defp change_debug_incident(change) do
    if failure_status?(change.status) do
      %{
        id: change.id,
        kind: "change_artifact",
        status: change.status,
        host: nil,
        command: change.command,
        deploy_profile: nil,
        failed_step: change.phase,
        failed_command: nil,
        exit_code: nil,
        path: change.path,
        summary_path: change.path,
        debug_pack_path: nil,
        plan_path: change.source_plan,
        transcript_path: nil,
        result_path: change.path,
        updated_at: change.updated_at,
        excerpt:
          [change.summary, change.path]
          |> Enum.reject(&is_nil/1)
          |> Enum.take(3),
        failure: true
      }
    end
  end

  defp failure_status?(nil), do: false

  defp failure_status?(status) when is_binary(status) do
    normalized = String.downcase(status)

    Enum.any?(
      ["fail", "error", "blocked", "denied", "timeout", "invalid"],
      &String.contains?(normalized, &1)
    )
  end

  defp failure_status?(_status), do: false

  defp load_control_state(_artifact_root, nil), do: nil

  defp load_control_state(artifact_root, cell_group_id) do
    [artifact_root, "control_state", "#{cell_group_id}.json"]
    |> Path.join()
    |> File.read()
    |> case do
      {:ok, body} ->
        case JSON.decode(body) do
          {:ok, payload} -> payload
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp path_updated_at(path) do
    path
    |> candidate_paths()
    |> Enum.map(&safe_updated_at/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix/1, fn ->
      DateTime.from_naive!(~N[1970-01-01 00:00:00], "Etc/UTC")
    end)
  end

  defp candidate_paths(path) do
    if File.dir?(path) do
      [path | Path.wildcard(Path.join(path, "**/*"))]
    else
      [path]
    end
  end

  defp safe_updated_at(path) do
    case File.stat(path) do
      {:ok, stat} ->
        stat.mtime
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")

      _ ->
        nil
    end
  end

  defp log_excerpt(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(-6)
  end

  defp classify_container(name, image) do
    downcased = String.downcase("#{name} #{image}")

    cond do
      contains_any?(downcased, [
        "ran-",
        "oaisoftwarealliance/oai",
        "oai-gnb",
        "oai-nr-ue",
        "oai-cu",
        "cucp",
        "cuup",
        " du",
        "gnb",
        "ue",
        "amf"
      ]) ->
        "ran"

      contains_any?(downcased, ["neartr-ric", "xapp", "flexric", "rustric", " agent "]) ->
        "agent"

      true ->
        "support"
    end
  end

  defp tone_from_status(status) when is_binary(status) do
    downcased = String.downcase(status)

    cond do
      String.contains?(downcased, "healthy") -> "healthy"
      String.contains?(downcased, "up") -> "running"
      String.contains?(downcased, "exited") -> "exited"
      true -> "unknown"
    end
  end

  defp health_ok?(container), do: container.tone in ["healthy", "running"]

  defp container_rank(container) do
    {domain_rank(container.domain), health_rank(container.tone), container.name}
  end

  defp domain_rank("ran"), do: 0
  defp domain_rank("agent"), do: 1
  defp domain_rank(_), do: 2

  defp health_rank("healthy"), do: 0
  defp health_rank("running"), do: 1
  defp health_rank("exited"), do: 2
  defp health_rank(_), do: 3

  defp label_value(nil, _key), do: nil

  defp label_value(labels, key) do
    labels
    |> split_csv()
    |> Enum.find_value(fn item ->
      case String.split(item, "=", parts: 2) do
        [^key, value] -> value
        _ -> nil
      end
    end)
  end

  defp split_csv(nil), do: []

  defp split_csv(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp contains_any?(value, needles) do
    Enum.any?(needles, &String.contains?(value, &1))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp fetch_value(map, key, default \\ nil)

  defp fetch_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp fetch_value(_value, _key, default), do: default

  defp to_string_value(nil), do: nil
  defp to_string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_value(value), do: value

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
