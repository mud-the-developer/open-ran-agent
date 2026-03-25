defmodule RanActionGateway.Runner do
  @moduledoc """
  Deterministic action runner for the bootstrap `ranctl` contract.
  """

  require Logger

  alias RanActionGateway.ArtifactRetention
  alias RanActionGateway.Change
  alias RanActionGateway.ControlState
  alias RanActionGateway.OaiRuntime
  alias RanActionGateway.Store

  @phases [:precheck, :plan, :apply, :verify, :rollback, :observe, :capture_artifacts]
  @change_commands [:precheck, :plan, :apply, :verify, :rollback]
  @scopes ~w(backend cell_group association incident gnb target_host ue_session ru_link core_link replacement_cutover)

  @spec phases() :: [atom()]
  def phases, do: @phases

  @spec execute(atom(), Change.t()) :: {:ok, map()} | {:error, map()}
  def execute(command, %Change{} = change) when command in @phases do
    Logger.metadata(
      change_id: change.change_id,
      cell_group: change.cell_group,
      incident_id: change.incident_id
    )

    Logger.info("ranctl #{command_to_string(command)} starting")

    result =
      with :ok <- validate(command, change) do
        do_execute(command, change)
      end

    log_result(command, result)
    result
  end

  @spec validate(atom(), Change.t()) :: :ok | {:error, map()}
  def validate(command, %Change{} = change) do
    errors =
      []
      |> require(:scope, change.scope)
      |> validate_scope(change.scope)
      |> validate_cell_group(change)
      |> validate_target_backend(change.target_backend)
      |> validate_verify_window(change.verify_window)
      |> validate_change_id(command, change.change_id)
      |> validate_reason(change.reason)
      |> validate_idempotency_key(change.idempotency_key)
      |> validate_observe_or_capture_identifiers(command, change)
      |> validate_approval_contract(command, change)

    case errors do
      [] ->
        :ok

      _ ->
        {:error,
         %{
           status: "invalid",
           command: command_to_string(command),
           errors: Enum.reverse(errors) |> Enum.map(&format_error/1)
         }}
    end
  end

  @spec pipeline(Change.t()) :: {:ok, [atom()]} | {:error, map()}
  def pipeline(%Change{} = change) do
    with :ok <- validate(:plan, change) do
      {:ok, [:precheck, :plan, :apply, :verify]}
    end
  end

  defp do_execute(:precheck, change) do
    runtime_precheck = runtime_precheck(change)
    config_report = RanConfig.validation_report()
    cell_group_check = validate_requested_cell_group(change)
    switch_policy = backend_switch_policy(change)
    control_state = control_state_snapshot(change)
    native_probe = maybe_native_probe(change)

    checks = [
      check("scope_valid", true),
      check(
        "target_backend_known",
        is_nil(change.target_backend) or change.target_backend in RanCore.supported_backends()
      ),
      check("verify_window_valid", valid_verify_window?(change.verify_window)),
      check("config_shape_present", config_report.status == :ok),
      check("cell_group_exists", cell_group_check == :ok),
      check("target_preprovisioned", preprovisioned?(switch_policy))
    ]

    checks =
      checks ++
        native_probe_checks(native_probe) ++
        operational_checks(change, control_state) ++ runtime_checks(runtime_precheck)

    failed? = Enum.any?(checks, &(&1["status"] == "failed"))

    {:ok,
     %{
       status: if(failed?, do: "failed", else: "ok"),
       command: "precheck",
       scope: change.scope,
       cell_group: change.cell_group,
       change_id: change.change_id,
       incident_id: change.incident_id,
       target_backend: maybe_to_string(change.target_backend),
       checks: checks,
       config_report: config_report,
       policy: format_policy(switch_policy),
       control_state: control_state,
       native_probe: native_probe,
       runtime: runtime_payload(runtime_precheck),
       next: if(failed?, do: ["observe"], else: ["plan"])
     }
     |> maybe_put_replacement_status(:precheck, change, checks)}
  end

  defp do_execute(:plan, change) do
    with {:ok, switch_policy} <- backend_switch_policy(change),
         {:ok, runtime_plan} <- runtime_plan(change) do
      rollback_target = infer_rollback_target(change, switch_policy)
      current_backend = change.current_backend || switch_policy.current_backend
      rollback_plan = build_rollback_plan(change, rollback_target)

      Store.ensure_root!()
      Store.write_json(Store.rollback_plan_path(change.change_id), rollback_plan)

      plan =
        %{
          status: "planned",
          command: "plan",
          scope: change.scope,
          cell_group: change.cell_group,
          change_id: change.change_id,
          incident_id: change.incident_id,
          target_backend: maybe_to_string(change.target_backend),
          current_backend: maybe_to_string(current_backend),
          rollback_target: maybe_to_string(rollback_target),
          allowed_targets: Enum.map(switch_policy.allowed_targets, &Atom.to_string/1),
          steps: ["precheck", "apply", "verify"],
          rollback_plan: rollback_plan,
          verify_window: change.verify_window,
          max_blast_radius: change.max_blast_radius,
          artifacts: [
            Store.plan_path(change.change_id),
            Store.rollback_plan_path(change.change_id)
          ]
        }
        |> put_optional("approval_required", approval_required?(:apply, change))
        |> put_optional("approval_fields_required", approval_fields_required(:apply, change))
        |> put_runtime_plan(runtime_plan)

      Store.write_json(Store.plan_path(change.change_id), plan)

      {:ok, Map.put(plan, :summary, "change plan prepared for #{change.scope}")}
    end
  end

  defp do_execute(:apply, change) do
    with {:ok, plan} <- load_plan(change.change_id),
         {:ok, approval} <- ensure_approval(:apply, change),
         {:ok, runtime_apply} <- maybe_apply_runtime(change),
         {:ok, control_state} <- maybe_apply_control_state(change, :apply) do
      approval_path = persist_approval(:apply, change, plan, approval)

      state =
        %{
          status: "applied",
          command: "apply",
          scope: change.scope,
          cell_group: change.cell_group,
          change_id: change.change_id,
          incident_id: change.incident_id,
          target_backend: plan["target_backend"],
          rollback_target: plan["rollback_target"],
          verify_window: plan["verify_window"],
          approval_ref: approval_path,
          rollback_plan_ref: existing_path(Store.rollback_plan_path(change.change_id)),
          control_state: control_state,
          applied_at: now_iso8601(),
          next: ["verify"],
          artifacts: [
            Store.change_state_path(change.change_id),
            approval_path,
            Store.rollback_plan_path(change.change_id)
          ]
        }
        |> put_optional("approved", approved?(change))
        |> put_runtime_result(runtime_apply)

      Store.write_json(Store.change_state_path(change.change_id), state)
      {:ok, state}
    end
  end

  defp do_execute(:verify, change) do
    with {:ok, state} <- load_change_state(change.change_id),
         {:ok, runtime_verify} <- maybe_verify_runtime(change) do
      control_state = control_state_snapshot(change)
      native_probe = maybe_native_probe(change)

      checks =
        Enum.map(extract_verify_checks(change, state), fn check ->
          %{
            "name" => check,
            "status" => verify_check_status(change, check, control_state)
          }
        end)
        |> Kernel.++(native_probe_checks(native_probe))
        |> maybe_append_runtime_verify(runtime_verify)

      failed? = Enum.any?(checks, &(&1["status"] == "failed"))

      result =
        %{
          status: if(failed?, do: "failed", else: "verified"),
          command: "verify",
          scope: change.scope,
          cell_group: change.cell_group,
          change_id: change.change_id,
          incident_id: change.incident_id,
          checks: checks,
          control_state: control_state,
          native_probe: native_probe,
          next: if(failed?, do: ["capture-artifacts", "rollback"], else: ["observe"]),
          artifacts: [Store.verify_path(change.change_id)]
        }
        |> put_runtime_result(runtime_verify)
        |> maybe_put_replacement_status(:verify, change, checks)

      Store.write_json(Store.verify_path(change.change_id), result)
      {:ok, result}
    end
  end

  defp do_execute(:rollback, change) do
    with {:ok, plan} <- load_plan(change.change_id),
         {:ok, rollback_plan} <- load_rollback_plan(change.change_id),
         {:ok, approval} <- ensure_approval(:rollback, change),
         {:ok, runtime_rollback} <- maybe_rollback_runtime(change),
         {:ok, control_state} <- maybe_apply_control_state(change, :rollback) do
      approval_path = persist_approval(:rollback, change, plan, approval)

      result =
        %{
          status: "rolled_back",
          command: "rollback",
          scope: change.scope,
          cell_group: change.cell_group,
          change_id: change.change_id,
          incident_id: change.incident_id,
          target_backend: plan["rollback_target"],
          restored_from: plan["target_backend"],
          rollback_plan: rollback_plan,
          approval_ref: approval_path,
          control_state: control_state,
          rolled_back_at: now_iso8601(),
          next: ["verify"],
          artifacts: [
            Store.change_state_path(change.change_id),
            approval_path,
            Store.rollback_plan_path(change.change_id)
          ]
        }
        |> put_optional("approved", approved?(change))
        |> put_runtime_result(runtime_rollback)

      Store.write_json(Store.change_state_path(change.change_id), result)
      {:ok, result}
    end
  end

  defp do_execute(:observe, change) do
    with {:ok, runtime_observe} <- maybe_observe_runtime(change) do
      config_report = RanConfig.validation_report()
      release_readiness = RanConfig.release_readiness()
      retention_plan = ArtifactRetention.plan()
      policy = format_policy(backend_switch_policy(change))
      control_state = control_state_snapshot(change)
      native_probe = native_probe_snapshot(change)

      incident_summary =
        incident_summary(change, runtime_observe, config_report, control_state, native_probe)

      {:ok,
       %{
         status: "observed",
         command: "observe",
         scope: change.scope,
         cell_group: change.cell_group,
         change_id: change.change_id,
         incident_id: change.incident_id,
         summary:
           observe_summary(change, runtime_observe, config_report, control_state, native_probe),
         incident_summary: incident_summary,
         snapshot: %{
           backend_profiles: Enum.map(RanCore.supported_backends(), &Atom.to_string/1),
           scheduler_adapters: ["cpu_scheduler", "cumac_scheduler"],
           artifact_root: Store.artifact_root(),
           recent_changes: recent_change_refs(6),
           retention: retention_snapshot(retention_plan)
         },
         config: %{
           profile: config_report.profile,
           status: config_report.status,
           cell_group: observed_cell_group(change),
           policy: policy,
           release_readiness: release_readiness
         },
         control_state: control_state,
         runtime: runtime_observe,
         native_probe: native_probe
       }}
    end
  end

  defp do_execute(:capture_artifacts, change) do
    ref = change.incident_id || change.change_id || "ad-hoc-capture"

    with {:ok, runtime_capture} <- maybe_capture_runtime(change) do
      snapshots = capture_supporting_snapshots(change, ref)
      bundle = capture_bundle(change, ref, runtime_capture, snapshots)

      bundle =
        %{
          status: "captured",
          command: "capture-artifacts",
          scope: change.scope,
          cell_group: change.cell_group,
          change_id: change.change_id,
          incident_id: change.incident_id,
          bundle: bundle
        }
        |> put_runtime_result(runtime_capture)

      path = Store.write_json(Store.capture_path(ref), bundle)
      {:ok, Map.update(bundle, :artifacts, [path], fn artifacts -> [path | artifacts] end)}
    end
  end

  defp require(errors, field, value) do
    if present?(value), do: errors, else: [{field, "is required"} | errors]
  end

  defp validate_scope(errors, scope) when scope in @scopes, do: errors
  defp validate_scope(errors, nil), do: errors

  defp validate_scope(errors, _scope),
    do: [{:scope, "must be one of #{@scopes |> Enum.join(", ")}"} | errors]

  defp validate_cell_group(errors, %Change{scope: "cell_group", cell_group: cell_group}) do
    require(errors, :cell_group, cell_group)
  end

  defp validate_cell_group(errors, _change), do: errors

  defp validate_target_backend(errors, nil), do: errors

  defp validate_target_backend(errors, backend) do
    if backend in RanCore.supported_backends() do
      errors
    else
      [
        {:target_backend,
         "must be one of #{Enum.join(Enum.map(RanCore.supported_backends(), &Atom.to_string/1), ", ")}"}
        | errors
      ]
    end
  end

  defp validate_verify_window(errors, %{"duration" => duration, "checks" => checks})
       when is_binary(duration) and is_list(checks),
       do: errors

  defp validate_verify_window(errors, %{duration: duration, checks: checks})
       when is_binary(duration) and is_list(checks),
       do: errors

  defp validate_verify_window(errors, _verify_window),
    do: [{:verify_window, "must include duration and checks"} | errors]

  defp validate_change_id(errors, command, change_id) when command in @change_commands do
    require(errors, :change_id, change_id)
  end

  defp validate_change_id(errors, _command, _change_id), do: errors

  defp validate_reason(errors, reason), do: require(errors, :reason, reason)

  defp validate_idempotency_key(errors, value), do: require(errors, :idempotency_key, value)

  defp validate_observe_or_capture_identifiers(errors, :observe, %Change{}), do: errors

  defp validate_observe_or_capture_identifiers(errors, :capture_artifacts, %Change{
         change_id: change_id,
         incident_id: incident_id
       }) do
    if present?(change_id) or present?(incident_id) do
      errors
    else
      [{:change_id, "or incident_id is required for capture-artifacts"} | errors]
    end
  end

  defp validate_observe_or_capture_identifiers(errors, _command, _change), do: errors

  defp validate_approval_contract(errors, command, %Change{} = change)
       when command in [:apply, :rollback] do
    if approved?(change) and
         not valid_approval_payload?(normalize_approval(change.approval, command)) do
      [{:approval, "must include approved_by, approved_at, ticket_ref, and source"} | errors]
    else
      errors
    end
  end

  defp validate_approval_contract(errors, _command, _change), do: errors

  defp load_plan(change_id) do
    case Store.read_json(Store.plan_path(change_id)) do
      {:ok, plan} ->
        {:ok, plan}

      {:error, :enoent} ->
        {:error,
         %{
           status: "missing_plan",
           command: "plan",
           errors: ["plan artifact not found for #{change_id}"]
         }}

      {:error, reason} ->
        {:error, %{status: "invalid_plan", command: "plan", errors: [inspect(reason)]}}
    end
  end

  defp load_change_state(change_id) do
    case Store.read_json(Store.change_state_path(change_id)) do
      {:ok, state} ->
        {:ok, state}

      {:error, :enoent} ->
        {:error,
         %{
           status: "missing_change_state",
           command: "verify",
           errors: ["apply must succeed before verify for #{change_id}"]
         }}

      {:error, reason} ->
        {:error, %{status: "invalid_change_state", command: "verify", errors: [inspect(reason)]}}
    end
  end

  defp load_rollback_plan(change_id) do
    case Store.read_json(Store.rollback_plan_path(change_id)) do
      {:ok, rollback_plan} ->
        {:ok, rollback_plan}

      {:error, :enoent} ->
        {:error,
         %{
           status: "missing_rollback_plan",
           command: "plan",
           errors: ["rollback plan artifact not found for #{change_id}"]
         }}

      {:error, reason} ->
        {:error, %{status: "invalid_rollback_plan", command: "plan", errors: [inspect(reason)]}}
    end
  end

  defp ensure_approval(command, %Change{} = change) do
    approval = normalize_approval(change.approval, command)

    cond do
      approval_required?(command, change) and not approved?(change) ->
        {:error,
         %{
           status: "approval_required",
           command: command_to_string(command),
           errors: ["approved=true is required for this action"]
         }}

      approval_required?(command, change) and not valid_approval_payload?(approval) ->
        {:error,
         %{
           status: "invalid_approval_evidence",
           command: command_to_string(command),
           errors: ["approval must include approved_by, approved_at, ticket_ref, and source"]
         }}

      true ->
        {:ok, approval}
    end
  end

  defp approval_required?(command, %Change{} = change) when command in [:apply, :rollback] do
    not change.dry_run and change.scope in ["backend", "cell_group", "association"]
  end

  defp approval_required?(_command, _change), do: false

  defp approval_fields_required(command, %Change{} = change) do
    if approval_required?(command, change) do
      ["approved", "approved_by", "approved_at", "ticket_ref", "source"]
    end
  end

  defp approved?(%Change{approval: approval}) when is_map(approval) do
    truthy?(Map.get(approval, :approved) || Map.get(approval, "approved"))
  end

  defp normalize_approval(approval, command) when is_map(approval) do
    %{
      "approved" => truthy?(Map.get(approval, :approved) || Map.get(approval, "approved")),
      "approved_by" => Map.get(approval, :approved_by) || Map.get(approval, "approved_by"),
      "approved_at" => Map.get(approval, :approved_at) || Map.get(approval, "approved_at"),
      "ticket_ref" => Map.get(approval, :ticket_ref) || Map.get(approval, "ticket_ref"),
      "source" => Map.get(approval, :source) || Map.get(approval, "source"),
      "evidence" => Map.get(approval, :evidence) || Map.get(approval, "evidence") || [],
      "command" => command_to_string(command)
    }
  end

  defp normalize_approval(_approval, command) do
    %{"approved" => false, "evidence" => [], "command" => command_to_string(command)}
  end

  defp valid_approval_payload?(approval) when is_map(approval) do
    truthy?(approval["approved"]) and
      Enum.all?(~w(approved_by approved_at ticket_ref source), &present?(approval[&1]))
  end

  defp valid_approval_payload?(_approval), do: false

  defp persist_approval(command, %Change{} = change, plan, approval) do
    payload = %{
      status: "approved",
      command: command_to_string(command),
      change_id: change.change_id,
      cell_group: change.cell_group,
      incident_id: change.incident_id,
      target_backend: plan["target_backend"],
      rollback_target: plan["rollback_target"],
      approval: approval,
      captured_at: now_iso8601()
    }

    Store.write_json(Store.approval_path(change.change_id, command_to_string(command)), payload)
  end

  defp infer_rollback_target(%Change{current_backend: current_backend}, _policy)
       when not is_nil(current_backend) do
    if current_backend in RanCore.supported_backends() do
      current_backend
    else
      infer_rollback_target(%Change{target_backend: current_backend}, nil)
    end
  end

  defp infer_rollback_target(%Change{}, %{rollback_target: rollback_target})
       when not is_nil(rollback_target),
       do: rollback_target

  defp infer_rollback_target(%Change{target_backend: :local_fapi_profile}, _policy),
    do: :stub_fapi_profile

  defp infer_rollback_target(%Change{target_backend: :aerial_fapi_profile}, _policy),
    do: :local_fapi_profile

  defp infer_rollback_target(%Change{}, _policy), do: :stub_fapi_profile

  defp extract_verify_checks(%Change{verify_window: %{checks: checks}}, _state)
       when is_list(checks),
       do: Enum.map(checks, &to_string/1)

  defp extract_verify_checks(%Change{verify_window: %{"checks" => checks}}, _state)
       when is_list(checks),
       do: Enum.map(checks, &to_string/1)

  defp extract_verify_checks(_change, _state), do: ["gateway_healthy"]

  defp verify_check_status(%Change{} = change, check, _control_state)
       when check in ["attach_freeze_active", "cell_group_drained", "drain_active", "drain_idle"] do
    if ControlState.check(change.cell_group, check) do
      "passed"
    else
      "failed"
    end
  end

  defp verify_check_status(%Change{metadata: metadata}, _check, _control_state) do
    if truthy?(metadata[:simulate_failure] || metadata["simulate_failure"]) do
      "failed"
    else
      "passed"
    end
  end

  defp maybe_put_replacement_status(payload, phase, %Change{} = change, _checks) do
    if replacement_scope?(change.scope) do
      replacement = replacement_metadata(change)
      base_status = payload[:status] || payload["status"]

      payload
      |> Map.put(:summary, replacement_summary(phase, change, base_status))
      |> Map.put(:gate_class, replacement_gate_class(phase, base_status))
      |> Map.put(:core_profile, replacement["core_profile"])
      |> Map.put(:core_link_status, replacement_core_link_status(phase, change, replacement, base_status))
      |> Map.put(:interface_status, replacement_interface_status(phase, change, replacement, base_status))
      |> maybe_put_attach_status(phase, change, replacement, base_status)
    else
      payload
    end
  end

  defp replacement_scope?(scope),
    do: scope in ~w(gnb target_host ue_session ru_link core_link replacement_cutover)

  defp replacement_metadata(%Change{metadata: metadata}) do
    metadata[:replacement] || metadata["replacement"] || %{}
  end

  defp replacement_gate_class(:precheck, "failed"), do: "blocked"
  defp replacement_gate_class(:precheck, _status), do: "degraded"
  defp replacement_gate_class(:verify, "failed"), do: "degraded"
  defp replacement_gate_class(:verify, _status), do: "pass"

  defp replacement_summary(phase, %Change{} = change, status) do
    target_role = replacement_metadata(change)["target_role"] || change.scope
    "#{phase |> Atom.to_string()} replacement #{target_role} status is #{status}"
  end

  defp replacement_core_link_status(phase, %Change{} = change, replacement, status) do
    core = replacement["open5gs_core"] || %{}
    profile = core["profile"] || replacement["core_profile"]

    %{
      status: if(status == "failed", do: "failed", else: "ok"),
      evidence_ref: replacement_evidence_ref(phase, change, "core-link"),
      reason:
        if(status == "failed",
          do: "replacement control surface has not yet proven the real Open5GS core path",
          else: nil
        ),
      profile: profile
    }
  end

  defp replacement_interface_status(phase, %Change{} = change, replacement, status) do
    replacement
    |> Map.get("required_interfaces", [])
    |> Enum.map(fn interface ->
      {interface,
       %{
         status: replacement_interface_state(status),
         evidence_ref: replacement_evidence_ref(phase, change, interface),
         reason: replacement_interface_reason(status)
       }}
    end)
    |> Enum.into(%{})
  end

  defp replacement_interface_state("failed"), do: "pending"
  defp replacement_interface_state(_status), do: "ok"

  defp replacement_interface_reason("failed"),
    do: "replacement evidence for this interface is not yet fully surfaced by the control surface"

  defp replacement_interface_reason(_status), do: nil

  defp maybe_put_attach_status(payload, phase, %Change{} = change, replacement, status) do
    if Enum.member?(replacement["acceptance_gates"] || [], "registration") do
      Map.put(payload, :attach_status, %{
        status: if(status == "failed", do: "pending", else: "ok"),
        evidence_ref: replacement_evidence_ref(phase, change, "attach"),
        reason: if(status == "failed", do: "replacement attach path is not yet fully proven", else: nil)
      })
    else
      payload
    end
  end

  defp replacement_evidence_ref(phase, %Change{} = change, suffix) do
    "artifacts/replacement/#{phase |> Atom.to_string()}/#{change.change_id}/#{suffix}.json"
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value), do: value

  defp check(name, true), do: %{"name" => name, "status" => "passed"}
  defp check(name, false), do: %{"name" => name, "status" => "failed"}

  defp valid_verify_window?(%{"duration" => duration, "checks" => checks})
       when is_binary(duration) and is_list(checks),
       do: true

  defp valid_verify_window?(%{duration: duration, checks: checks})
       when is_binary(duration) and is_list(checks),
       do: true

  defp valid_verify_window?(_), do: false

  defp validate_requested_cell_group(%Change{scope: "cell_group", cell_group: cell_group}) do
    case RanConfig.find_cell_group(cell_group) do
      {:ok, _} -> :ok
      {:error, :not_found} -> {:error, :cell_group_not_found}
    end
  end

  defp validate_requested_cell_group(_change), do: :ok

  defp backend_switch_policy(%Change{
         scope: "cell_group",
         cell_group: cell_group,
         target_backend: target_backend
       })
       when not is_nil(cell_group) do
    RanConfig.backend_switch_policy(cell_group, target_backend)
  end

  defp backend_switch_policy(%Change{}) do
    {:ok,
     %{
       current_backend: nil,
       rollback_target: nil,
       allowed_targets: [],
       target_backend: nil,
       target_preprovisioned: true
     }}
  end

  defp present?(value), do: value not in [nil, "", false]

  defp truthy?(value), do: value in [true, "true", 1, "1", true]

  defp command_to_string(command), do: command |> Atom.to_string() |> String.replace("_", "-")

  defp put_optional(payload, _key, nil), do: payload
  defp put_optional(payload, key, value), do: Map.put(payload, key, value)

  defp preprovisioned?({:ok, %{target_preprovisioned: allowed?}}), do: allowed?
  defp preprovisioned?({:error, _}), do: false

  defp control_state_snapshot(%Change{cell_group: nil}), do: nil

  defp control_state_snapshot(%Change{cell_group: cell_group}),
    do: ControlState.snapshot(cell_group)

  defp operational_checks(%Change{} = change, control_state) do
    change
    |> requested_check_names()
    |> Enum.filter(&(&1 in ControlState.supported_checks()))
    |> Enum.uniq()
    |> Enum.map(fn check_name ->
      check(check_name, control_check_status(change, check_name, control_state))
    end)
  end

  defp control_check_status(%Change{} = change, check_name, nil),
    do: ControlState.check(change.cell_group, check_name)

  defp control_check_status(_change, "attach_freeze_active", control_state),
    do: get_in(control_state, ["attach_freeze", "status"]) == "active"

  defp control_check_status(_change, "cell_group_drained", control_state),
    do: get_in(control_state, ["drain", "status"]) == "drained"

  defp control_check_status(_change, "drain_active", control_state),
    do: get_in(control_state, ["drain", "status"]) in ["draining", "drained"]

  defp control_check_status(_change, "drain_idle", control_state),
    do: get_in(control_state, ["drain", "status"]) == "idle"

  defp control_check_status(%Change{} = change, check_name, _control_state),
    do: ControlState.check(change.cell_group, check_name)

  defp format_policy({:ok, policy}) do
    %{
      current_backend: maybe_to_string(Map.get(policy, :current_backend)),
      rollback_target: maybe_to_string(Map.get(policy, :rollback_target)),
      allowed_targets: Enum.map(Map.get(policy, :allowed_targets, []), &Atom.to_string/1),
      target_backend: maybe_to_string(Map.get(policy, :target_backend)),
      target_preprovisioned: Map.get(policy, :target_preprovisioned)
    }
  end

  defp format_policy({:error, %{policy: policy}}), do: policy
  defp format_policy(_), do: nil

  defp format_error({field, message}) do
    %{
      field: Atom.to_string(field),
      message: message
    }
  end

  defp build_rollback_plan(%Change{} = change, rollback_target) do
    %{
      status: "prepared",
      command: "rollback",
      change_id: change.change_id,
      cell_group: change.cell_group,
      incident_id: change.incident_id,
      target_backend: maybe_to_string(rollback_target),
      verify_window: change.verify_window,
      source_plan: Store.plan_path(change.change_id),
      artifact_path: Store.rollback_plan_path(change.change_id)
    }
  end

  defp log_result(command, {:ok, payload}) do
    Logger.info(
      "ranctl #{command_to_string(command)} finished with status #{payload[:status] || payload["status"]}"
    )
  end

  defp log_result(command, {:error, payload}) do
    Logger.warning(
      "ranctl #{command_to_string(command)} failed with status #{payload[:status] || payload["status"]}"
    )
  end

  defp runtime_precheck(%Change{cell_group: cell_group, metadata: metadata}) do
    if OaiRuntime.runtime_requested?(metadata) do
      OaiRuntime.precheck(cell_group, metadata)
    else
      {:ok, nil}
    end
  end

  defp runtime_plan(%Change{change_id: change_id, cell_group: cell_group, metadata: metadata}) do
    if OaiRuntime.runtime_requested?(metadata) do
      OaiRuntime.plan(change_id, cell_group, metadata)
    else
      {:ok, nil}
    end
  end

  defp maybe_apply_runtime(%Change{
         change_id: change_id,
         cell_group: cell_group,
         metadata: metadata
       }) do
    if OaiRuntime.runtime_requested?(metadata) do
      OaiRuntime.apply(change_id, cell_group, metadata)
    else
      {:ok, nil}
    end
  end

  defp maybe_verify_runtime(%Change{
         change_id: change_id,
         cell_group: cell_group,
         metadata: metadata
       }) do
    if OaiRuntime.runtime_requested?(metadata) do
      OaiRuntime.verify(change_id, cell_group, metadata)
    else
      {:ok, nil}
    end
  end

  defp maybe_rollback_runtime(%Change{
         change_id: change_id,
         cell_group: cell_group,
         metadata: metadata
       }) do
    if OaiRuntime.runtime_requested?(metadata) do
      OaiRuntime.rollback(change_id, cell_group, metadata)
    else
      {:ok, nil}
    end
  end

  defp maybe_observe_runtime(%Change{cell_group: cell_group, metadata: metadata}) do
    if OaiRuntime.runtime_requested?(metadata) do
      OaiRuntime.observe(cell_group, metadata)
    else
      {:ok, nil}
    end
  end

  defp maybe_capture_runtime(%Change{
         change_id: change_id,
         cell_group: cell_group,
         metadata: metadata
       }) do
    if OaiRuntime.runtime_requested?(metadata) do
      OaiRuntime.capture_artifacts(change_id, cell_group, metadata)
    else
      {:ok, nil}
    end
  end

  defp runtime_checks({:ok, %{checks: checks}}) when is_list(checks), do: checks
  defp runtime_checks({:error, _payload}), do: [check("oai_runtime_resolved", false)]
  defp runtime_checks(_), do: []

  defp native_probe_checks(nil), do: []

  defp native_probe_checks(native_probe) do
    [
      check("native_probe_resolved", true),
      check("native_probe_host_ready", native_probe_status(native_probe) == "ready"),
      check("native_probe_activation_gate_clear", native_probe_activation_ok?(native_probe))
    ]
  end

  defp runtime_payload({:ok, nil}), do: nil
  defp runtime_payload({:ok, payload}), do: payload
  defp runtime_payload({:error, payload}), do: payload
  defp runtime_payload(_), do: nil

  defp put_runtime_plan(payload, {:ok, nil}), do: payload
  defp put_runtime_plan(payload, nil), do: payload

  defp put_runtime_plan(payload, runtime_plan) do
    payload
    |> Map.put("runtime_mode", runtime_plan.runtime_mode)
    |> Map.put("runtime_plan", runtime_plan)
    |> Map.update!(:artifacts, fn artifacts ->
      artifacts ++ [runtime_plan.compose_path]
    end)
  end

  defp put_runtime_result(payload, {:ok, nil}), do: payload
  defp put_runtime_result(payload, nil), do: payload

  defp put_runtime_result(payload, runtime_result) do
    payload
    |> Map.put("runtime_mode", runtime_result.runtime_mode)
    |> Map.put("runtime_result", runtime_result)
    |> maybe_add_runtime_artifacts(runtime_result)
  end

  defp maybe_add_runtime_artifacts(payload, %{"compose_path" => compose_path}) do
    Map.update(payload, :artifacts, [compose_path], fn artifacts ->
      artifacts ++ [compose_path]
    end)
  end

  defp maybe_add_runtime_artifacts(payload, %{compose_path: compose_path} = runtime_result) do
    payload
    |> Map.update(:artifacts, [compose_path], fn artifacts -> artifacts ++ [compose_path] end)
    |> maybe_add_runtime_logs(runtime_result)
  end

  defp maybe_add_runtime_artifacts(payload, _runtime_result), do: payload

  defp maybe_add_runtime_logs(payload, %{logs: logs}) when is_list(logs) do
    Map.update(payload, :artifacts, logs, fn artifacts -> artifacts ++ logs end)
  end

  defp maybe_add_runtime_logs(payload, _runtime_result), do: payload

  defp maybe_append_runtime_verify(checks, nil), do: checks

  defp maybe_append_runtime_verify(checks, %{containers: containers} = runtime_verify) do
    runtime_checks = Map.get(runtime_verify, :checks, [])

    checks ++
      runtime_checks ++
      Enum.map(containers, fn container ->
        %{
          "name" => "runtime:#{container["name"]}",
          "status" => if(container["running"], do: "passed", else: "failed")
        }
      end)
  end

  defp maybe_append_runtime_verify(checks, _), do: checks

  defp observe_summary(
         %Change{cell_group: cell_group},
         runtime_observe,
         config_report,
         control_state,
         native_probe
       ) do
    runtime_status =
      case runtime_observe do
        %{containers: containers} when is_list(containers) ->
          "#{length(containers)} runtime containers"

        _ ->
          "no runtime overlay"
      end

    control_status =
      case control_state do
        %{"attach_freeze" => freeze, "drain" => drain} ->
          "freeze #{freeze["status"]} / drain #{drain["status"]}"

        _ ->
          "no control state"
      end

    [
      "config profile #{config_report.profile}",
      "validation #{config_report.status}",
      cell_group && "cell group #{cell_group}",
      runtime_status,
      control_status,
      probe_status_summary(native_probe)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" / ")
  end

  defp retention_snapshot(plan) do
    %{
      policy: plan.policy,
      summary: plan.summary,
      prune_candidates: Enum.take(plan.prune, 5)
    }
  end

  defp incident_summary(
         %Change{} = change,
         runtime_observe,
         config_report,
         control_state,
         native_probe
       ) do
    reasons =
      []
      |> maybe_add_reason(config_report.status != :ok, "config validation is not clean")
      |> maybe_add_reason(runtime_unhealthy?(runtime_observe), "runtime surface is degraded")
      |> maybe_add_reason(
        native_probe_status(native_probe) == "blocked",
        "native host probe is blocked"
      )
      |> maybe_add_reason(
        native_probe_status(native_probe) == "degraded",
        "native host probe is degraded"
      )
      |> maybe_add_reason(
        get_in(control_state || %{}, ["attach_freeze", "status"]) == "active",
        "attach freeze is active"
      )
      |> maybe_add_reason(
        get_in(control_state || %{}, ["drain", "status"]) in ["draining", "drained"],
        "cell group drain workflow is active"
      )
      |> Enum.reverse()

    %{
      severity: incident_severity(reasons),
      reasons: reasons,
      suggested_next: suggested_next_steps(change, reasons, control_state, native_probe),
      runtime_mode:
        case runtime_observe do
          %{runtime_mode: mode} -> mode
          _ -> nil
        end,
      native_probe: native_probe
    }
  end

  defp observed_cell_group(%Change{cell_group: nil}), do: nil

  defp observed_cell_group(%Change{cell_group: cell_group}) do
    case RanConfig.find_cell_group(cell_group) do
      {:ok, config} -> normalize_cell_group(config)
      {:error, :not_found} -> nil
    end
  end

  defp capture_bundle(%Change{} = change, ref, runtime_capture, snapshots) do
    %{
      manifest: %{
        ref: ref,
        captured_at: now_iso8601(),
        scope: change.scope,
        cell_group: change.cell_group,
        change_id: change.change_id,
        incident_id: change.incident_id,
        artifact_root: Store.artifact_root()
      },
      workflow: %{
        plan: existing_path(change.change_id && Store.plan_path(change.change_id)),
        change_state:
          existing_path(change.change_id && Store.change_state_path(change.change_id)),
        verify: existing_path(change.change_id && Store.verify_path(change.change_id)),
        rollback_plan:
          existing_path(change.change_id && Store.rollback_plan_path(change.change_id)),
        approvals: approval_artifacts(change.change_id),
        config_snapshot: snapshots.config_snapshot,
        control_snapshot: snapshots.control_snapshot,
        probe_snapshot: snapshots.probe_snapshot,
        capture: Store.capture_path(ref)
      },
      control_state: snapshots.control_state,
      native_probe: snapshots.native_probe,
      runtime: %{
        compose_path: runtime_capture_path(runtime_capture, :compose_path),
        logs: runtime_logs(runtime_capture),
        configs: runtime_configs(change.change_id)
      }
    }
  end

  defp existing_path(nil), do: nil

  defp existing_path(path) do
    if File.exists?(path), do: path, else: nil
  end

  defp runtime_capture_path(nil, _key), do: nil

  defp runtime_capture_path(runtime_capture, key) when is_map(runtime_capture) do
    Map.get(runtime_capture, key) || Map.get(runtime_capture, Atom.to_string(key))
  end

  defp runtime_logs(runtime_capture) when is_map(runtime_capture) do
    Map.get(runtime_capture, :logs) || Map.get(runtime_capture, "logs") || []
  end

  defp runtime_logs(_runtime_capture), do: []

  defp runtime_configs(nil), do: []

  defp runtime_configs(change_id) do
    change_id
    |> Store.runtime_conf_dir()
    |> Path.join("*.conf")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp recent_change_refs(limit) do
    ["plans", "changes", "verify", "captures", "approvals", "rollback_plans"]
    |> Enum.flat_map(fn kind ->
      Path.wildcard(Path.join([Store.artifact_root(), kind, "*.json"]))
    end)
    |> Enum.map(fn path ->
      {:ok, stat} = File.stat(path)
      %{path: path, mtime: stat.mtime}
    end)
    |> Enum.sort_by(& &1.mtime, :desc)
    |> Enum.take(limit)
    |> Enum.map(& &1.path)
  end

  defp approval_artifacts(nil), do: []

  defp approval_artifacts(change_id) do
    Store.artifact_root()
    |> Path.join("approvals/#{change_id}-*.json")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp normalize_cell_group(cell_group) when is_map(cell_group) do
    %{
      id: Map.get(cell_group, :id) || Map.get(cell_group, "id"),
      du: Map.get(cell_group, :du) || Map.get(cell_group, "du"),
      backend: atom_or_value(Map.get(cell_group, :backend) || Map.get(cell_group, "backend")),
      scheduler:
        atom_or_value(Map.get(cell_group, :scheduler) || Map.get(cell_group, "scheduler")),
      failover_targets:
        (Map.get(cell_group, :failover_targets) || Map.get(cell_group, "failover_targets") || [])
        |> Enum.map(&atom_or_value/1)
    }
  end

  defp maybe_apply_control_state(%Change{} = change, command) do
    control = control_metadata(change)

    if control == %{} do
      {:ok, control_state_snapshot(change)}
    else
      ControlState.apply_intents(change.cell_group, control,
        change_id: change.change_id,
        command: command,
        reason: change.reason
      )
    end
  end

  defp control_metadata(%Change{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, :control) || Map.get(metadata, "control") do
      control when is_map(control) -> control
      _ -> %{}
    end
  end

  defp requested_check_names(%Change{verify_window: %{checks: checks}}) when is_list(checks),
    do: Enum.map(checks, &to_string/1)

  defp requested_check_names(%Change{verify_window: %{"checks" => checks}}) when is_list(checks),
    do: Enum.map(checks, &to_string/1)

  defp requested_check_names(_change), do: []

  defp capture_supporting_snapshots(%Change{} = change, ref) do
    config_snapshot = capture_config_snapshot(ref, change)
    control_snapshot = capture_control_snapshot(ref, change)
    native_probe = native_probe_snapshot(change)
    probe_snapshot = capture_probe_snapshot(ref, change, native_probe)

    %{
      config_snapshot: config_snapshot,
      control_snapshot: control_snapshot,
      probe_snapshot: probe_snapshot,
      control_state: control_state_snapshot(change),
      native_probe: native_probe
    }
  end

  defp capture_config_snapshot(ref, %Change{} = change) do
    payload = %{
      captured_at: now_iso8601(),
      change_id: change.change_id,
      incident_id: change.incident_id,
      cell_group: change.cell_group,
      profile: RanConfig.current_profile(),
      validation: RanConfig.validation_report(),
      requested_cell_group: observed_cell_group(change)
    }

    Store.write_json(Store.config_snapshot_path(ref), payload)
  end

  defp capture_control_snapshot(ref, %Change{} = change) do
    payload = %{
      captured_at: now_iso8601(),
      change_id: change.change_id,
      incident_id: change.incident_id,
      cell_group: change.cell_group,
      control_state: control_state_snapshot(change)
    }

    Store.write_json(Store.control_snapshot_path(ref), payload)
  end

  defp capture_probe_snapshot(_ref, _change, nil), do: nil

  defp capture_probe_snapshot(ref, %Change{} = change, native_probe) do
    payload = %{
      captured_at: now_iso8601(),
      change_id: change.change_id,
      incident_id: change.incident_id,
      cell_group: change.cell_group,
      native_probe: native_probe
    }

    Store.write_json(Store.probe_snapshot_path(ref), payload)
  end

  defp maybe_add_reason(reasons, true, reason), do: [reason | reasons]
  defp maybe_add_reason(reasons, false, _reason), do: reasons

  defp incident_severity([]), do: "info"
  defp incident_severity([_single]), do: "attention"
  defp incident_severity(_reasons), do: "warning"

  defp suggested_next_steps(%Change{} = _change, reasons, control_state, native_probe) do
    []
    |> maybe_add_step(
      "run precheck again after restoring validation",
      "config validation is not clean" in reasons
    )
    |> maybe_add_step(
      "capture artifacts and inspect runtime logs",
      "runtime surface is degraded" in reasons
    )
    |> maybe_add_step(
      native_probe_recovery_step(native_probe),
      "native host probe is blocked" in reasons or "native host probe is degraded" in reasons
    )
    |> maybe_add_step(
      "release attach freeze after the maintenance window",
      get_in(control_state || %{}, ["attach_freeze", "status"]) == "active"
    )
    |> maybe_add_step(
      "complete verify and clear drain when the cell group is stable",
      get_in(control_state || %{}, ["drain", "status"]) in ["draining", "drained"]
    )
  end

  defp maybe_add_step(steps, step, true), do: steps ++ [step]
  defp maybe_add_step(steps, _step, false), do: steps

  defp runtime_unhealthy?(%{containers: containers}) when is_list(containers) do
    Enum.any?(containers, fn container ->
      status =
        container[:health] || container["health"] || container[:status] || container["status"]

      to_string(status) not in ["healthy", "running"]
    end)
  end

  defp runtime_unhealthy?(_runtime_observe), do: false

  defp maybe_native_probe(%Change{metadata: metadata} = change) when is_map(metadata) do
    case Map.get(metadata, :native_probe) || Map.get(metadata, "native_probe") do
      probe when is_map(probe) -> run_native_probe(change, probe)
      _ -> nil
    end
  end

  defp maybe_native_probe(_change), do: nil

  defp run_native_probe(%Change{} = change, probe) do
    profile = native_probe_profile(change, probe)

    with true <- profile in RanCore.supported_backends(),
         {:ok, backend} <- RanFapiCore.Profile.backend_module(profile),
         {:ok, session} <- backend.open_session(native_probe_opts(change, probe)),
         {:ok, before_health} <- backend.health(session) do
      activation =
        case backend.activate_cell(session, cell_group_id: change.cell_group) do
          :ok -> %{status: "ok"}
          {:error, reason} -> %{status: "failed", reason: atom_or_value(reason)}
        end

      health =
        case backend.health(session) do
          {:ok, after_health} -> after_health
          {:error, _reason} -> before_health
        end

      _ = backend.terminate(session)

      native_probe_payload(profile, health, activation)
    else
      false ->
        nil

      {:error, reason} ->
        %{
          profile: atom_or_value(profile),
          status: "failed",
          activation_status: "failed",
          error: atom_or_value(reason)
        }
    end
  end

  defp native_probe_profile(%Change{} = change, probe) do
    probe_profile =
      Map.get(probe, "backend_profile") ||
        Map.get(probe, :backend_profile) ||
        change.target_backend ||
        change.current_backend

    parse_backend_profile(probe_profile)
  end

  defp native_probe_opts(%Change{} = change, probe) do
    opts = [
      cell_group_id: change.cell_group,
      session_payload:
        Map.get(probe, "session_payload") || Map.get(probe, :session_payload) || %{}
    ]

    case Map.get(probe, "transport") || Map.get(probe, :transport) do
      nil ->
        opts

      transport when is_binary(transport) ->
        Keyword.put(opts, :transport, String.to_atom(transport))

      transport ->
        Keyword.put(opts, :transport, transport)
    end
  end

  defp native_probe_payload(profile, health, activation) when is_map(health) do
    checks = Map.get(health, :checks) || Map.get(health, "checks") || %{}
    host_probe_status = checks["host_probe_status"]

    session_status =
      Map.get(health, :session_status) || Map.get(health, "session_status") || "unknown"

    %{
      profile: atom_or_value(profile),
      status: if(host_probe_status == "ready", do: "ready", else: host_probe_status || "unknown"),
      activation_status: activation.status,
      activation_reason: Map.get(activation, :reason),
      backend_family: checks["backend_family"],
      worker_kind: checks["worker_kind"],
      strict_host_probe: checks["strict_host_probe"],
      activation_gate: checks["activation_gate"],
      handshake_target: checks["handshake_target"],
      probe_evidence_ref: checks["probe_evidence_ref"],
      probe_checked_at: checks["probe_checked_at"],
      probe_required_resources: checks["probe_required_resources"] || [],
      probe_observations: checks["probe_observations"] || %{},
      host_probe_ref: checks["host_probe_ref"],
      host_probe_status: host_probe_status,
      host_probe_mode: checks["host_probe_mode"],
      host_probe_failures: checks["host_probe_failures"] || [],
      probe_failure_count: checks["probe_failure_count"],
      handshake_state: checks["handshake_state"],
      session_status: atom_or_value(session_status)
    }
  end

  defp parse_backend_profile(value) when is_atom(value), do: value

  defp parse_backend_profile(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> nil
    end
  end

  defp parse_backend_profile(_value), do: nil

  defp native_probe_snapshot(%Change{change_id: nil}), do: nil

  defp native_probe_snapshot(%Change{change_id: change_id}) do
    [
      Store.verify_path(change_id),
      Store.change_state_path(change_id),
      Store.plan_path(change_id)
    ]
    |> Enum.find_value(&extract_native_probe_from_artifact/1)
  end

  defp extract_native_probe_from_artifact(path) do
    with true <- File.exists?(path),
         {:ok, payload} <- Store.read_json(path),
         contract when is_map(contract) <- native_probe_candidate(payload),
         summary when is_map(summary) <- native_probe_summary(contract) do
      Map.put(summary, :artifact_path, path)
    else
      _ -> nil
    end
  end

  defp native_probe_candidate(payload) when is_map(payload) do
    [
      payload["native_probe"],
      payload["runtime_result"],
      payload["native_contract"],
      get_in(payload, ["incident_summary", "native_probe"])
    ]
    |> Enum.find(&is_map/1)
  end

  defp native_probe_candidate(_payload), do: nil

  defp native_probe_summary(contract) when is_map(contract) do
    summary =
      %{
        backend_family: fetch_probe_field(contract, "backend_family"),
        worker_kind: fetch_probe_field(contract, "worker_kind"),
        strict_host_probe: fetch_probe_field(contract, "strict_host_probe"),
        activation_gate: fetch_probe_field(contract, "activation_gate"),
        handshake_target: fetch_probe_field(contract, "handshake_target"),
        probe_evidence_ref: fetch_probe_field(contract, "probe_evidence_ref"),
        probe_checked_at: fetch_probe_field(contract, "probe_checked_at"),
        probe_required_resources: fetch_probe_field(contract, "probe_required_resources"),
        probe_observations: fetch_probe_field(contract, "probe_observations"),
        host_probe_ref: fetch_probe_field(contract, "host_probe_ref"),
        host_probe_status: fetch_probe_field(contract, "host_probe_status"),
        host_probe_mode: fetch_probe_field(contract, "host_probe_mode"),
        host_probe_failures: fetch_probe_field(contract, "host_probe_failures"),
        probe_failure_count: fetch_probe_field(contract, "probe_failure_count"),
        handshake_state: fetch_probe_field(contract, "handshake_state")
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.into(%{})

    if map_size(summary) == 0, do: nil, else: summary
  end

  defp native_probe_summary(_contract), do: nil

  defp fetch_probe_field(contract, key) do
    Map.get(contract, key) || get_in(contract, ["health", "checks", key])
  end

  defp probe_status_summary(nil), do: nil

  defp probe_status_summary(native_probe) do
    status = native_probe_status(native_probe)

    case status do
      nil -> nil
      value -> "native probe #{value}"
    end
  end

  defp native_probe_status(nil), do: nil

  defp native_probe_status(native_probe),
    do: Map.get(native_probe, :host_probe_status) || native_probe["host_probe_status"]

  defp native_probe_activation_ok?(nil), do: false

  defp native_probe_activation_ok?(native_probe) do
    activation_status =
      Map.get(native_probe, :activation_status) || native_probe["activation_status"]

    activation_status in ["ok", "skipped"]
  end

  defp native_probe_recovery_step(nil),
    do: "restore required host resources for the native adapter"

  defp native_probe_recovery_step(native_probe) do
    resources =
      Map.get(native_probe, :probe_required_resources) ||
        native_probe["probe_required_resources"] ||
        []

    failures =
      Map.get(native_probe, :host_probe_failures) ||
        native_probe["host_probe_failures"] ||
        []

    target =
      [Enum.join(List.wrap(resources), ", "), Enum.join(List.wrap(failures), ", ")]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" / ")

    if target == "" do
      "restore required host resources for the native adapter"
    else
      "restore native host resources: #{target}"
    end
  end

  defp atom_or_value(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_or_value(value), do: value

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
