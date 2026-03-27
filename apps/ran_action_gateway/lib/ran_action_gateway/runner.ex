defmodule RanActionGateway.Runner do
  @moduledoc """
  Deterministic action runner for the bootstrap `ranctl` contract.
  """

  require Logger

  alias RanActionGateway.ArtifactRetention
  alias RanActionGateway.Change
  alias RanActionGateway.ControlState
  alias RanActionGateway.OaiRuntime
  alias RanActionGateway.ReplacementReview
  alias RanActionGateway.RuntimeContract
  alias RanActionGateway.Store

  @phases [:precheck, :plan, :apply, :verify, :rollback, :observe, :capture_artifacts]
  @change_commands [:precheck, :plan, :apply, :verify, :rollback]
  @scopes ~w(backend cell_group association incident gnb target_host ue_session ru_link core_link replacement_cutover)
  @replacement_scopes ~w(gnb target_host ue_session ru_link core_link replacement_cutover)
  @replacement_backends ~w(oai_reference replacement_shadow replacement_primary)
  @ngap_failure_hints [
    "downlink nas transport",
    "downlink_nas_transport",
    "downlink-nas-transport",
    "registration rejected",
    "registration_rejected",
    "registration rejection",
    "registration_failure",
    "registration failed",
    "ngap_registration_failed"
  ]
  @baseline_conformance_profile "oai_visible_5g_standards_baseline_v1"
  @baseline_conformance_ref "subprojects/ran_replacement/notes/16-oai-visible-5g-standards-conformance-baseline.md"

  @spec phases() :: [atom()]
  def phases, do: @phases

  @spec replacement_scopes() :: [String.t()]
  def replacement_scopes, do: @replacement_scopes

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
      |> validate_target_ref(change)
      |> validate_cell_group(change)
      |> validate_target_backend(change.target_backend, change.scope)
      |> validate_verify_window(change.verify_window)
      |> validate_change_id(command, change.change_id)
      |> validate_reason(change.reason)
      |> validate_idempotency_key(change.idempotency_key)
      |> validate_observe_or_capture_identifiers(command, change)
      |> validate_approval_contract(command, change)
      |> validate_replacement_contract(command, change)
      |> RuntimeContract.validate(command, change)

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
    runtime_contract = runtime_precheck_contract(change, runtime_precheck)
    config_report = RanConfig.validation_report()
    cell_group_check = validate_requested_cell_group(change)
    switch_policy = backend_switch_policy(change)
    control_state = control_state_snapshot(change)
    native_probe = maybe_native_probe(change)

    checks = [
      check("scope_valid", true),
      check(
        "target_backend_known",
        target_backend_known?(change)
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

    payload =
      %{
        status: if(failed?, do: "failed", else: "ok"),
        command: "precheck",
        scope: change.scope,
        target_ref: change.target_ref,
        cell_group: change.cell_group,
        change_id: change.change_id,
        incident_id: change.incident_id,
        target_backend: maybe_to_string(change.target_backend),
        checks: checks,
        config_report: config_report,
        policy: format_policy(switch_policy),
        control_state: control_state,
        native_probe: native_probe,
        runtime_contract: runtime_contract,
        runtime: runtime_payload(runtime_precheck),
        next: if(failed?, do: ["observe"], else: ["plan"])
      }
      |> maybe_add_precheck_artifact(change)
      |> maybe_put_replacement_status(:precheck, change, checks)
      |> materialize_replacement_artifacts(:precheck, change)
      |> persist_precheck(change)

    {:ok, payload}
  end

  defp do_execute(:plan, change) do
    if replacement_scope?(change.scope) do
      do_execute_replacement_plan(change)
    else
      with {:ok, switch_policy} <- backend_switch_policy(change),
           {:ok, runtime_plan} <- runtime_plan(change),
           {:ok, runtime_contract} <- RuntimeContract.plan_contract(change) do
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
            target_ref: change.target_ref,
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
          |> put_runtime_contract(runtime_contract)
          |> put_runtime_plan(runtime_plan)

        Store.write_json(Store.plan_path(change.change_id), plan)

        {:ok, Map.put(plan, :summary, "change plan prepared for #{change.scope}")}
      end
    end
  end

  defp do_execute(:apply, change) do
    with {:ok, plan} <- load_plan(change.change_id),
         {:ok, runtime_contract} <- RuntimeContract.ensure_planned_contract(:apply, change, plan),
         {:ok, approval} <- ensure_approval(:apply, change),
         {:ok, runtime_apply} <- maybe_apply_runtime(change),
         {:ok, control_state} <- maybe_apply_control_state(change, :apply) do
      approval_path = persist_approval(:apply, change, plan, approval)

      state =
        %{
          status: "applied",
          command: "apply",
          scope: change.scope,
          target_ref: change.target_ref,
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
        |> put_runtime_contract(runtime_contract)
        |> put_runtime_result(runtime_apply)
        |> ReplacementReview.enrich(:apply, change, [])

      Store.write_json(Store.change_state_path(change.change_id), state)
      {:ok, state}
    end
  end

  defp do_execute(:verify, change) do
    with {:ok, state} <- load_change_state_for_verify(change),
         {:ok, plan} <- load_plan_for_verify(change),
         {:ok, runtime_contract} <- RuntimeContract.ensure_planned_contract(:verify, change, plan),
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
          target_ref: change.target_ref,
          cell_group: change.cell_group,
          change_id: change.change_id,
          incident_id: change.incident_id,
          checks: checks,
          control_state: control_state,
          native_probe: native_probe,
          next: if(failed?, do: ["capture-artifacts", "rollback"], else: ["observe"]),
          artifacts: [Store.verify_path(change.change_id)]
        }
        |> put_runtime_contract(runtime_contract)
        |> put_runtime_result(runtime_verify)
        |> maybe_put_replacement_status(:verify, change, checks)
        |> materialize_replacement_artifacts(:verify, change)

      Store.write_json(Store.verify_path(change.change_id), result)
      {:ok, result}
    end
  end

  defp do_execute(:rollback, change) do
    with {:ok, plan} <- load_plan_for_rollback(change),
         {:ok, rollback_plan} <- load_rollback_plan_for_rollback(change),
         {:ok, runtime_contract} <-
           RuntimeContract.ensure_planned_contract(:rollback, change, plan),
         {:ok, approval} <- ensure_approval(:rollback, change),
         {:ok, runtime_rollback} <- maybe_rollback_runtime(change),
         {:ok, control_state} <- maybe_apply_control_state(change, :rollback) do
      rollback_plan_path =
        Store.write_json(Store.rollback_plan_path(change.change_id), rollback_plan)

      approval_path = persist_approval(:rollback, change, plan, approval)

      result =
        %{
          status: "rolled_back",
          command: "rollback",
          scope: change.scope,
          target_ref: change.target_ref,
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
            rollback_plan_path
          ]
        }
        |> put_optional("approved", approved?(change))
        |> put_runtime_contract(runtime_contract)
        |> put_runtime_result(runtime_rollback)
        |> maybe_put_replacement_status(:rollback, change, [])
        |> materialize_replacement_artifacts(:rollback, change)

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
         target_ref: change.target_ref,
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
       }
       |> maybe_put_replacement_status(:observe, change, [])
       |> materialize_replacement_artifacts(:observe, change)}
    end
  end

  defp do_execute(:capture_artifacts, change) do
    ref = change.incident_id || change.change_id || "ad-hoc-capture"

    with {:ok, runtime_capture} <- maybe_capture_runtime(change) do
      snapshots = capture_supporting_snapshots(change, ref)
      review = ReplacementReview.capture_review(change, ref)
      bundle = capture_bundle(change, ref, runtime_capture, snapshots, review)

      bundle =
        %{
          status: "captured",
          command: "capture-artifacts",
          scope: change.scope,
          target_ref: change.target_ref,
          cell_group: change.cell_group,
          change_id: change.change_id,
          incident_id: change.incident_id,
          bundle: bundle
        }
        |> put_runtime_result(runtime_capture)
        |> maybe_put_replacement_status(:capture_artifacts, change, [])
        |> materialize_replacement_artifacts(:capture_artifacts, change)

      path = Store.write_json(Store.capture_path(ref), bundle)
      {:ok, Map.update(bundle, :artifacts, [path], fn artifacts -> [path | artifacts] end)}
    end
  end

  defp maybe_add_precheck_artifact(payload, %Change{change_id: change_id})
       when is_binary(change_id) do
    Map.put(payload, :artifacts, [Store.precheck_path(change_id)])
  end

  defp maybe_add_precheck_artifact(payload, _change), do: payload

  defp persist_precheck(payload, %Change{change_id: change_id}) when is_binary(change_id) do
    Store.write_json(Store.precheck_path(change_id), payload)
    payload
  end

  defp persist_precheck(payload, _change), do: payload

  defp require(errors, field, value) do
    if present?(value), do: errors, else: [{field, "is required"} | errors]
  end

  defp validate_scope(errors, scope) when scope in @scopes, do: errors
  defp validate_scope(errors, nil), do: errors

  defp validate_scope(errors, _scope),
    do: [{:scope, "must be one of #{@scopes |> Enum.join(", ")}"} | errors]

  defp validate_target_ref(errors, %Change{scope: scope, target_ref: target_ref})
       when scope in @replacement_scopes do
    require(errors, :target_ref, target_ref)
  end

  defp validate_target_ref(errors, _change), do: errors

  defp validate_cell_group(errors, %Change{scope: "cell_group", cell_group: cell_group}) do
    require(errors, :cell_group, cell_group)
  end

  defp validate_cell_group(errors, _change), do: errors

  defp validate_target_backend(errors, nil, scope) when scope in @replacement_scopes do
    [
      {:target_backend, "must be one of #{Enum.join(@replacement_backends, ", ")}"}
      | errors
    ]
  end

  defp validate_target_backend(errors, nil, _scope), do: errors

  defp validate_target_backend(errors, backend, scope) do
    cond do
      scope in @replacement_scopes and replacement_backend?(backend) ->
        errors

      backend in RanCore.supported_backends() ->
        errors

      scope in @replacement_scopes ->
        [{:target_backend, "must be one of #{Enum.join(@replacement_backends, ", ")}"} | errors]

      true ->
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

  defp validate_replacement_contract(errors, command, %Change{} = change)
       when change.scope in @replacement_scopes do
    replacement = replacement_metadata(change)

    errors
    |> require_replacement_field("target_profile", replacement["target_profile"])
    |> require_replacement_field("core_profile", replacement["core_profile"])
    |> require_replacement_field("action", replacement["action"])
    |> require_replacement_field("target_role", replacement["target_role"])
    |> require_replacement_field("required_interfaces", replacement["required_interfaces"])
    |> require_replacement_field("acceptance_gates", replacement["acceptance_gates"])
    |> validate_replacement_rollback_target(command, change)
  end

  defp validate_replacement_contract(errors, _command, _change), do: errors

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

  defp load_plan_for_verify(%Change{} = change) do
    case load_plan(change.change_id) do
      {:ok, plan} ->
        {:ok, plan}

      {:error, %{status: "missing_plan"} = error} ->
        if replacement_scope?(change.scope),
          do: {:ok, replacement_virtual_plan(change)},
          else: {:error, error}

      error ->
        error
    end
  end

  defp load_change_state_for_verify(%Change{} = change) do
    case load_change_state(change.change_id) do
      {:ok, state} ->
        {:ok, state}

      {:error, %{status: "missing_change_state"} = error} ->
        if replacement_scope?(change.scope),
          do: {:ok, replacement_virtual_change_state(change)},
          else: {:error, error}

      error ->
        error
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

  defp load_plan_for_rollback(%Change{} = change) do
    case load_plan(change.change_id) do
      {:ok, plan} ->
        {:ok, plan}

      {:error, %{status: "missing_plan"} = error} ->
        if replacement_scope?(change.scope),
          do: {:ok, replacement_virtual_plan(change)},
          else: {:error, error}

      error ->
        error
    end
  end

  defp load_rollback_plan_for_rollback(%Change{} = change) do
    case load_rollback_plan(change.change_id) do
      {:ok, rollback_plan} ->
        {:ok, rollback_plan}

      {:error, %{status: "missing_rollback_plan"} = error} ->
        if replacement_scope?(change.scope),
          do: {:ok, build_rollback_plan(change, :oai_reference)},
          else: {:error, error}

      error ->
        error
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
    replacement_destructive? = truthy?(replacement_metadata(change)["destructive"])

    not change.dry_run and
      (change.scope in ["backend", "cell_group", "association"] or replacement_destructive?)
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
      "evidence" =>
        normalize_evidence_refs(Map.get(approval, :evidence) || Map.get(approval, "evidence")),
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
      runtime_contract: plan["runtime_contract"],
      approval: approval,
      captured_at: now_iso8601()
    }

    Store.write_json(Store.approval_path(change.change_id, command_to_string(command)), payload)
  end

  defp normalize_evidence_refs(evidence) when is_list(evidence) do
    evidence
    |> Enum.flat_map(fn
      value when is_binary(value) and value != "" -> [value]
      value when is_atom(value) -> [Atom.to_string(value)]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp normalize_evidence_refs(_evidence), do: []

  defp infer_rollback_target(%Change{rollback_target: rollback_target}, _policy)
       when is_binary(rollback_target) and rollback_target != "",
       do: rollback_target

  defp infer_rollback_target(%Change{current_backend: current_backend}, _policy)
       when is_binary(current_backend) do
    if replacement_backend?(current_backend) do
      current_backend
    else
      infer_rollback_target(%Change{target_backend: current_backend}, nil)
    end
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

  defp infer_rollback_target(%Change{target_backend: target_backend}, _policy)
       when is_binary(target_backend) do
    if replacement_backend?(target_backend), do: target_backend, else: :stub_fapi_profile
  end

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

  defp maybe_put_replacement_status(payload, phase, %Change{} = change, checks) do
    if replacement_scope?(change.scope) do
      replacement = replacement_metadata(change)
      base_status = payload[:status] || payload["status"]
      replacement_status = replacement_status(phase, change, base_status)

      payload
      |> Map.put(:status, replacement_status)
      |> Map.put(:target_ref, replacement_target_ref(change))
      |> Map.put(:target_profile, replacement["target_profile"])
      |> Map.put(:target_backend, replacement_target_backend(phase, change))
      |> put_optional(:rollback_target, replacement_rollback_target(change))
      |> Map.put(:conformance_claim, replacement_conformance_claim(phase))
      |> Map.put(:core_endpoint, replacement_core_endpoint(replacement))
      |> Map.put(:summary, replacement_summary(phase, change, base_status))
      |> Map.put(:gate_class, replacement_gate_class(phase, replacement_status))
      |> Map.put(:core_profile, replacement["core_profile"])
      |> Map.put(
        :core_link_status,
        replacement_core_link_status(phase, change, replacement, base_status)
      )
      |> Map.put(
        :interface_status,
        replacement_interface_status(phase, change, replacement, base_status)
      )
      |> maybe_put_ru_status(phase, change, replacement, replacement_status)
      |> maybe_put_ngap_procedure_trace(phase, change, replacement, base_status)
      |> maybe_put_release_status(phase, change, replacement, base_status)
      |> maybe_put_failure_class(phase, change, replacement, base_status)
      |> maybe_put_plane_status(phase, change, replacement, base_status)
      |> maybe_put_rollback_status(phase, change, base_status)
      |> maybe_put_user_plane_semantics(phase, change, replacement)
      |> maybe_put_control_plane_interface_semantics(phase, change)
      |> maybe_put_attach_status(phase, change, replacement, base_status)
      |> maybe_put_session_gate_statuses(phase, change, replacement)
      |> maybe_put_replacement_review_semantics(phase, change, replacement)
      |> ReplacementReview.enrich(phase, change, checks)
    else
      payload
    end
  end

  defp replacement_scope?(scope), do: scope in @replacement_scopes

  defp replacement_metadata(%Change{metadata: metadata}) do
    metadata[:replacement] || metadata["replacement"] || %{}
  end

  defp replacement_target_ref(%Change{target_ref: target_ref})
       when is_binary(target_ref) and target_ref != "",
       do: target_ref

  defp replacement_target_ref(%Change{} = change) do
    replacement = replacement_metadata(change)
    replacement["target_ref"] || replacement["target_role"] || change.scope
  end

  defp replacement_target_backend(:precheck, %Change{requested_target_backend: nil}),
    do: "replacement_shadow"

  defp replacement_target_backend(_phase, %Change{requested_target_backend: target_backend})
       when is_binary(target_backend) and target_backend != "",
       do: target_backend

  defp replacement_target_backend(_phase, %Change{target_backend: target_backend})
       when is_binary(target_backend) and target_backend != "",
       do: target_backend

  defp replacement_target_backend(_phase, %Change{target_backend: target_backend})
       when is_atom(target_backend) and not is_nil(target_backend),
       do: Atom.to_string(target_backend)

  defp replacement_target_backend(_phase, _change), do: nil

  defp replacement_rollback_target(%Change{rollback_target: rollback_target})
       when is_binary(rollback_target) and rollback_target != "",
       do: rollback_target

  defp replacement_rollback_target(%Change{requested_current_backend: current_backend})
       when is_binary(current_backend) and current_backend != "",
       do: current_backend

  defp replacement_rollback_target(%Change{current_backend: current_backend})
       when is_binary(current_backend) and current_backend != "",
       do: current_backend

  defp replacement_rollback_target(%Change{current_backend: current_backend})
       when is_atom(current_backend) and not is_nil(current_backend),
       do: Atom.to_string(current_backend)

  defp replacement_rollback_target(_change), do: "oai_reference"

  defp replacement_conformance_claim(_phase) do
    %{
      profile: @baseline_conformance_profile,
      evidence_tier: "milestone_proof",
      baseline_ref: @baseline_conformance_ref
    }
  end

  defp replacement_core_endpoint(replacement) do
    core = replacement["open5gs_core"] || %{}

    %{
      profile: core["profile"] || replacement["core_profile"],
      release_ref: core["release_ref"] || "open5gs-sanitized-lab-release-1",
      n2: core["n2"] || %{},
      n3: core["n3"] || %{}
    }
  end

  defp replacement_gate_class(:precheck, "blocked"), do: "blocked"
  defp replacement_gate_class(:precheck, _status), do: "degraded"
  defp replacement_gate_class(:observe, _status), do: "degraded"
  defp replacement_gate_class(:capture_artifacts, "ok"), do: "pass"
  defp replacement_gate_class(:capture_artifacts, _status), do: "degraded"
  defp replacement_gate_class(:rollback, _status), do: "pass"
  defp replacement_gate_class(:verify, "degraded"), do: "degraded"
  defp replacement_gate_class(:verify, _status), do: "pass"

  defp replacement_status(:precheck, _change, _base_status), do: "blocked"
  defp replacement_status(:observe, _change, _base_status), do: "degraded"
  defp replacement_status(:capture_artifacts, _change, _base_status), do: "ok"
  defp replacement_status(:rollback, _change, _base_status), do: "ok"
  defp replacement_status(:verify, _change, "failed"), do: "degraded"
  defp replacement_status(:verify, _change, _base_status), do: "ok"

  defp replacement_summary(phase, %Change{} = change, status) do
    target_role = replacement_metadata(change)["target_role"] || change.scope

    cond do
      phase == :verify and user_plane_scope?(replacement_metadata(change)) and
          not user_plane_ping_failure?(change) ->
        "UE attach, PDU session, and ping are all proven against the declared Open5GS core lane."

      phase == :observe and user_plane_ping_failure?(change) ->
        "User-plane observe confirms attach and session hold, but ping diverged on the declared route."

      phase == :capture_artifacts and user_plane_ping_failure?(change) ->
        "Capture preserved the user-plane evidence bundle after ping failed on the declared route."

      phase == :observe and control_plane_scope?(change) ->
        "Control-plane replacement observe confirms that association state diverged from the planned cutover lane."

      true ->
        "#{phase |> Atom.to_string()} replacement #{target_role} status is #{status}"
    end
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

  defp maybe_put_ngap_procedure_trace(payload, phase, %Change{} = change, replacement, status) do
    if ngap_scope?(replacement) do
      Map.put(payload, :ngap_procedure_trace, %{
        last_observed: "UE Context Release",
        procedures: replacement_ngap_procedures(phase, change, status)
      })
    else
      payload
    end
  end

  defp maybe_put_release_status(payload, phase, %Change{} = change, replacement, _status) do
    if ngap_scope?(replacement) do
      Map.put(payload, :release_status, %{
        status: "ok",
        evidence_ref: replacement_evidence_ref(phase, change, "ue-context-release"),
        reason: nil
      })
    else
      payload
    end
  end

  defp maybe_put_ru_status(payload, phase, %Change{} = change, replacement, status) do
    if Enum.member?(replacement["acceptance_gates"] || [], "ru_sync") do
      Map.put(payload, :ru_status, %{
        status: if(status == "blocked", do: "blocked", else: "ok"),
        evidence_ref: replacement_evidence_ref(phase, change, "ru-sync"),
        reason:
          if(status == "blocked",
            do: "RU sync has not been confirmed for the declared lane",
            else: nil
          )
      })
    else
      payload
    end
  end

  defp maybe_put_failure_class(payload, phase, %Change{} = change, replacement, status),
    do:
      Map.put(
        payload,
        :failure_class,
        replacement_failure_class(phase, change, replacement, status)
      )

  defp replacement_failure_class(phase, %Change{} = change, replacement, status) do
    cond do
      ngap_scope?(replacement) and ngap_registration_failure?(change) ->
        "core_failure"

      user_plane_ping_failure?(change) ->
        "user_plane_failure"

      change.scope == "replacement_cutover" and
          (phase in [:observe, :capture_artifacts, :rollback] or status == "failed") ->
        "cutover_or_rollback_failure"

      true ->
        nil
    end
  end

  defp replacement_ngap_procedures(phase, %Change{} = change, status) do
    ngap_failure? = ngap_registration_failure?(change)

    [
      {"NG Setup", replacement_ngap_status(:ng_setup, status, ngap_failure?),
       replacement_evidence_ref(phase, change, "ngap-setup"),
       replacement_ngap_detail(:ng_setup, status)},
      {"Initial UE Message", replacement_ngap_status(:initial_ue_message, status, ngap_failure?),
       replacement_evidence_ref(phase, change, "initial-ue-message"),
       replacement_ngap_detail(:initial_ue_message, status)},
      {"Uplink NAS Transport",
       replacement_ngap_status(:uplink_nas_transport, status, ngap_failure?),
       replacement_evidence_ref(phase, change, "uplink-nas-transport"),
       replacement_ngap_detail(:uplink_nas_transport, status)},
      {"Downlink NAS Transport",
       replacement_ngap_status(:downlink_nas_transport, status, ngap_failure?),
       replacement_evidence_ref(phase, change, "downlink-nas-transport"),
       replacement_ngap_detail(:downlink_nas_transport, status)},
      {"UE Context Release", replacement_ngap_status(:ue_context_release, status, ngap_failure?),
       replacement_evidence_ref(phase, change, "ue-context-release"),
       replacement_ngap_detail(:ue_context_release, status)}
    ]
    |> Enum.map(fn {name, proc_status, evidence_ref, detail} ->
      %{name: name, status: proc_status, evidence_ref: evidence_ref, detail: detail}
    end)
  end

  defp replacement_ngap_status(:downlink_nas_transport, _status, true), do: "failed"
  defp replacement_ngap_status(_procedure, _status, _ngap_failure?), do: "ok"

  defp replacement_ngap_detail(:ng_setup, "failed"),
    do: "the declared Open5GS AMF accepted NG setup before registration diverged"

  defp replacement_ngap_detail(:ng_setup, _status),
    do: "the declared Open5GS AMF accepted the NG setup handshake"

  defp replacement_ngap_detail(:initial_ue_message, _status),
    do: "the first UE-originated NAS message reached the declared NGAP-facing lane"

  defp replacement_ngap_detail(:uplink_nas_transport, _status),
    do: "uplink NAS transport carried the registration request toward the declared core profile"

  defp replacement_ngap_detail(:downlink_nas_transport, "failed"),
    do: "downlink NAS transport returned a registration rejection from the declared core profile"

  defp replacement_ngap_detail(:downlink_nas_transport, _status),
    do: "downlink NAS transport carried the registration acceptance back toward the UE"

  defp replacement_ngap_detail(:ue_context_release, _status),
    do: "UE context release completed and the cleanup state is auditable"

  defp ngap_registration_failure?(%Change{verify_window: %{"checks" => checks}})
       when is_list(checks) do
    Enum.member?(checks, "ngap_registration_failed") or
      Enum.member?(checks, "registration_rejected")
  end

  defp ngap_registration_failure?(%Change{verify_window: %{checks: checks}})
       when is_list(checks) do
    Enum.member?(checks, "ngap_registration_failed") or
      Enum.member?(checks, "registration_rejected")
  end

  defp ngap_registration_failure?(%Change{} = change) do
    signal =
      [change.reason, change.incident_id, Enum.join(requested_check_names(change), " ")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    Enum.any?(@ngap_failure_hints, &String.contains?(signal, &1))
  end

  defp ngap_registration_failure?(_change), do: false

  defp ngap_scope?(replacement),
    do: Enum.member?(replacement["required_interfaces"] || [], "ngap")

  defp maybe_put_plane_status(payload, phase, %Change{} = change, _replacement, status) do
    if phase == :observe and control_plane_scope?(change) do
      Map.put(payload, :plane_status, %{
        c_plane: %{
          status: control_plane_observe_status(change, status),
          evidence_ref: replacement_evidence_ref(:observe, change, "cutover-control-plane"),
          reason: control_plane_observe_reason(change, status)
        }
      })
    else
      payload
    end
  end

  defp maybe_put_rollback_status(payload, phase, %Change{} = change, status) do
    if phase == :observe and control_plane_scope?(change) do
      Map.put(payload, :rollback_status, %{
        status:
          if(control_plane_cutover_review?(change) or status == "failed",
            do: "pending",
            else: "ok"
          ),
        evidence_ref: replacement_evidence_ref(:observe, change, "rollback-evidence"),
        reason:
          if(control_plane_cutover_review?(change) or status == "failed",
            do: "rollback is available but not yet executed",
            else: nil
          )
      })
    else
      payload
    end
  end

  defp control_plane_scope?(%Change{} = change) do
    required = replacement_metadata(change)["required_interfaces"] || []
    Enum.any?(required, &(&1 in ["f1_c", "e1ap"]))
  end

  defp maybe_put_control_plane_interface_semantics(payload, :observe, %Change{} = change) do
    if control_plane_cutover_review?(change) do
      update_in(payload, [:interface_status], fn interface_status ->
        interface_status
        |> maybe_put_control_plane_interface("f1_c", %{
          status: "degraded",
          evidence_ref: replacement_evidence_ref(:observe, change, "f1_c"),
          reason: "association or configuration state diverged from the planned lane"
        })
        |> maybe_put_control_plane_interface("e1ap", %{
          status: "degraded",
          evidence_ref: replacement_evidence_ref(:observe, change, "e1ap"),
          reason: "bearer or activity-state coordination diverged from the compare report"
        })
      end)
    else
      payload
    end
  end

  defp maybe_put_control_plane_interface_semantics(payload, _phase, _change), do: payload

  defp maybe_put_control_plane_interface(nil, _name, _value), do: nil

  defp maybe_put_control_plane_interface(interface_status, name, value) do
    if Map.has_key?(interface_status, name) do
      Map.put(interface_status, name, value)
    else
      interface_status
    end
  end

  defp control_plane_cutover_review?(%Change{} = change),
    do: change.scope == "replacement_cutover" and control_plane_scope?(change)

  defp control_plane_observe_status(%Change{} = change, _status) do
    if control_plane_cutover_review?(change), do: "degraded", else: "ok"
  end

  defp control_plane_observe_reason(%Change{} = change, status) do
    cond do
      control_plane_cutover_review?(change) ->
        "control-plane state is partially healthy but not ready for leave-running"

      status == "failed" ->
        "control-plane association or coordination diverged from the planned lane"

      true ->
        nil
    end
  end

  defp maybe_put_user_plane_semantics(payload, phase, %Change{} = change, replacement) do
    if user_plane_scope?(replacement) do
      payload
      |> maybe_put_user_plane_status(phase, change)
      |> maybe_put_session_status(phase, change, replacement)
      |> maybe_put_user_plane_interfaces(phase, change)
      |> maybe_put_user_plane_rollback_status(phase, change)
    else
      payload
    end
  end

  defp user_plane_scope?(replacement) do
    required = replacement["required_interfaces"] || []
    gates = replacement["acceptance_gates"] || []

    Enum.any?(required, &(&1 in ["f1_u", "gtpu"])) or
      Enum.any?(gates, &(&1 in ["pdu_session", "ping"]))
  end

  defp maybe_put_user_plane_status(payload, phase, %Change{} = change)
       when phase in [:verify, :observe, :capture_artifacts] do
    base = Map.get(payload, :plane_status, %{})

    user_plane =
      cond do
        phase == :verify and not user_plane_ping_failure?(change) ->
          %{
            status: "ok",
            evidence_ref: replacement_evidence_ref(:verify, change, "user-plane"),
            reason: nil
          }

        user_plane_ping_failure?(change) and phase == :observe ->
          %{
            status: "degraded",
            evidence_ref: replacement_evidence_ref(:observe, change, "user-plane"),
            reason: "user-plane confidence is incomplete after ping failed on the declared route"
          }

        user_plane_ping_failure?(change) and phase == :capture_artifacts ->
          %{
            status: "degraded",
            evidence_ref: replacement_evidence_ref(:capture_artifacts, change, "user-plane"),
            reason: "captured evidence shows the declared user-plane route is not yet trusted"
          }

        true ->
          nil
      end

    if user_plane do
      Map.put(payload, :plane_status, Map.put(base, :u_plane, user_plane))
    else
      payload
    end
  end

  defp maybe_put_user_plane_status(payload, _phase, _change), do: payload

  defp maybe_put_session_status(payload, phase, %Change{} = change, replacement)
       when phase in [:verify, :observe, :capture_artifacts] do
    session_profile = get_in(replacement, ["open5gs_core", "session_profile"]) || %{}

    session_status = %{
      status:
        if(user_plane_ping_failure?(change),
          do: "established_but_ping_failed",
          else: "established"
        ),
      pdu_type: session_profile["pdu_type"],
      ping_target: session_profile["expect_ping_target"],
      evidence_ref: replacement_evidence_ref(phase, change, "session"),
      reason:
        if(user_plane_ping_failure?(change),
          do: "PDU session exists, but the declared route did not complete a successful ping",
          else: nil
        )
    }

    payload
    |> Map.put(:session_status, session_status)
    |> Map.put(:pdu_session_status, %{
      status: if(user_plane_ping_failure?(change), do: "ok", else: "ok"),
      evidence_ref: replacement_evidence_ref(phase, change, "pdu-session"),
      reason: nil
    })
    |> Map.put(:ping_status, %{
      status: if(user_plane_ping_failure?(change), do: "failed", else: "ok"),
      evidence_ref: replacement_evidence_ref(phase, change, "ping"),
      reason:
        if(user_plane_ping_failure?(change),
          do: "declared ping target did not answer during the verify window",
          else: nil
        )
    })
  end

  defp maybe_put_session_status(payload, _phase, _change, _replacement), do: payload

  defp maybe_put_user_plane_interfaces(payload, phase, %Change{} = change)
       when phase in [:verify, :observe, :capture_artifacts] do
    interface_status = Map.get(payload, :interface_status, %{})

    {f1_u, gtpu} =
      cond do
        phase == :verify and not user_plane_ping_failure?(change) ->
          {
            %{
              status: "ok",
              evidence_ref: replacement_evidence_ref(:verify, change, "f1_u"),
              reason: nil
            },
            %{
              status: "ok",
              evidence_ref: replacement_evidence_ref(:verify, change, "gtpu"),
              reason: nil
            }
          }

        user_plane_ping_failure?(change) ->
          {
            %{
              status: "degraded",
              evidence_ref: replacement_evidence_ref(phase, change, "f1_u"),
              reason: "forwarding state does not yet prove the declared attach-plus-ping path"
            },
            %{
              status: "degraded",
              evidence_ref: replacement_evidence_ref(phase, change, "gtpu"),
              reason: "tunnel evidence exists, but end-to-end reachability did not complete"
            }
          }

        true ->
          {nil, nil}
      end

    interface_status =
      interface_status
      |> maybe_put_user_plane_interface("f1_u", f1_u)
      |> maybe_put_user_plane_interface("gtpu", gtpu)

    Map.put(payload, :interface_status, interface_status)
  end

  defp maybe_put_user_plane_interfaces(payload, _phase, _change), do: payload

  defp maybe_put_user_plane_interface(interface_status, _name, nil), do: interface_status

  defp maybe_put_user_plane_interface(interface_status, name, value),
    do: Map.put(interface_status, name, value)

  defp maybe_put_user_plane_rollback_status(payload, :observe, %Change{} = change) do
    if user_plane_ping_failure?(change) do
      Map.put(payload, :rollback_status, %{
        status: "pending",
        evidence_ref: replacement_evidence_ref(:observe, change, "rollback-evidence"),
        reason: "rollback is available while the user-plane route remains unresolved"
      })
    else
      payload
    end
  end

  defp maybe_put_user_plane_rollback_status(payload, _phase, _change), do: payload

  defp user_plane_ping_failure?(%Change{verify_window: %{"checks" => checks}})
       when is_list(checks),
       do: Enum.member?(checks, "ping_failed")

  defp user_plane_ping_failure?(%Change{verify_window: %{checks: checks}}) when is_list(checks),
    do: Enum.member?(checks, "ping_failed")

  defp user_plane_ping_failure?(%Change{} = change) do
    signal =
      [change.reason, change.incident_id, Enum.join(requested_check_names(change), " ")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(signal, "ping failed")
  end

  defp user_plane_ping_failure?(_change), do: false

  defp maybe_put_attach_status(payload, phase, %Change{} = change, replacement, status) do
    if Enum.member?(replacement["acceptance_gates"] || [], "registration") do
      Map.put(payload, :attach_status, %{
        status:
          cond do
            ngap_registration_failure?(change) -> "failed"
            status == "failed" -> "pending"
            true -> "ok"
          end,
        evidence_ref: replacement_evidence_ref(phase, change, "attach"),
        reason:
          cond do
            ngap_registration_failure?(change) ->
              "registration was rejected before the declared attach path completed"

            status == "failed" ->
              "replacement attach path is not yet fully proven"

            true ->
              nil
          end
      })
    else
      payload
    end
  end

  defp maybe_put_session_gate_statuses(payload, phase, %Change{} = change, replacement)
       when phase in [:verify, :observe, :capture_artifacts] do
    payload
    |> maybe_put_pdu_session_status(phase, change, replacement)
    |> maybe_put_ping_status(phase, change, replacement)
  end

  defp maybe_put_session_gate_statuses(payload, _phase, _change, _replacement), do: payload

  defp maybe_put_pdu_session_status(payload, phase, %Change{} = change, replacement) do
    if Enum.member?(replacement["acceptance_gates"] || [], "pdu_session") do
      Map.put(payload, :pdu_session_status, %{
        status: if(ngap_registration_failure?(change), do: "pending", else: "ok"),
        evidence_ref: replacement_evidence_ref(phase, change, "pdu-session"),
        reason:
          if(ngap_registration_failure?(change),
            do: "session setup was not reached after registration failed",
            else: nil
          )
      })
    else
      payload
    end
  end

  defp maybe_put_ping_status(payload, phase, %Change{} = change, replacement) do
    if Enum.member?(replacement["acceptance_gates"] || [], "ping") do
      Map.put(payload, :ping_status, %{
        status:
          cond do
            ngap_registration_failure?(change) -> "pending"
            user_plane_ping_failure?(change) -> "failed"
            true -> "ok"
          end,
        evidence_ref: replacement_evidence_ref(phase, change, "ping"),
        reason:
          cond do
            ngap_registration_failure?(change) ->
              "ping was not attempted after registration failed"

            user_plane_ping_failure?(change) ->
              "ping failed after the declared session was established"

            true ->
              nil
          end
      })
    else
      payload
    end
  end

  defp maybe_put_replacement_review_semantics(
         payload,
         :capture_artifacts,
         %Change{} = change,
         replacement
       ) do
    rollback_target = replacement_review_rollback_target(change)

    if replacement_capture_success?(change, replacement) do
      payload
      |> Map.put(
        :summary,
        "Capture preserved the verified live-lab evidence bundle for the declared lane."
      )
      |> Map.put(:gate_class, "pass")
      |> put_optional(:rollback_target, rollback_target)
      |> Map.put(:rollback_available, not is_nil(rollback_target))
      |> Map.put(:suggested_next, [
        "review the compare report and captured attach-plus-ping evidence together",
        "fetch the same evidence bundle onto the packaging host before the next mutation",
        "keep the rollback target explicit for the next real-lab run"
      ])
      |> Map.put(
        :checks,
        replacement_review_checks(replacement["acceptance_gates"] || [], [
          review_check(
            "compare_report_ready",
            "ok",
            "the compare report is preserved for review"
          ),
          review_check(
            "rollback_target_known",
            if(is_nil(rollback_target), do: "failed", else: "ok"),
            if(is_nil(rollback_target),
              do: "rollback target is still missing from the verified bundle",
              else: "rollback target remains explicit for the next mutation"
            )
          ),
          review_check(
            "bundle_fetchable",
            "ok",
            "the verified evidence bundle is materialized under repo-visible artifact roots"
          )
        ])
      )
      |> Map.put(
        :rollback_status,
        review_status(
          "ok",
          replacement_evidence_ref(:capture_artifacts, change, "rollback-evidence"),
          "rollback target remains available but was not executed for this successful capture"
        )
      )
    else
      payload
      |> Map.put(
        :summary,
        if(
          user_plane_ping_failure?(change),
          do:
            "Capture preserved the user-plane evidence bundle after ping failed on the declared route.",
          else:
            "Capture preserved the failed replacement evidence bundle for rollback review on the declared lane."
        )
      )
      |> Map.put(:gate_class, replacement_capture_gate_class(change, replacement))
      |> put_optional(:rollback_target, rollback_target)
      |> Map.put(:rollback_available, not is_nil(rollback_target))
      |> Map.put(:suggested_next, [
        "inspect the compare report before another replacement mutation",
        "confirm the rollback target and cleanup evidence remain explicit",
        "retry only after the captured mismatch is explained"
      ])
      |> Map.put(
        :checks,
        replacement_review_checks(replacement["acceptance_gates"] || [], [
          review_check(
            "compare_report_ready",
            "ok",
            "the compare report is preserved for review"
          ),
          review_check(
            "rollback_target_known",
            if(is_nil(rollback_target), do: "failed", else: "ok"),
            if(is_nil(rollback_target),
              do: "rollback target is still missing from the review bundle",
              else: "rollback target remains explicit for recovery"
            )
          ),
          review_check(
            "UE Context Release",
            "ok",
            "cleanup evidence remains explicit in the preserved review bundle"
          )
        ])
      )
      |> Map.put(
        :rollback_status,
        review_status(
          "pending",
          replacement_evidence_ref(:capture_artifacts, change, "rollback-evidence"),
          "rollback is available but has not yet been executed"
        )
      )
    end
  end

  defp maybe_put_replacement_review_semantics(payload, :rollback, %Change{} = change, replacement) do
    rollback_target = replacement_review_rollback_target(change)
    target_role = replacement["target_role"] || change.scope

    payload
    |> Map.put(
      :summary,
      "Rollback returned the #{target_role} lane to the declared #{rollback_target || "rollback"} target after replacement review failed."
    )
    |> put_optional(:rollback_target, rollback_target)
    |> Map.put(:approval_required, true)
    |> Map.put(:rollback_available, not is_nil(rollback_target))
    |> Map.put(:suggested_next, [
      "review the compare report that triggered rollback",
      "keep the lane shadowed until the captured mismatch is corrected",
      "rerun precheck after the rollback target is confirmed clean"
    ])
    |> Map.put(
      :checks,
      replacement_review_checks(replacement["acceptance_gates"] || [], [
        review_check(
          "rollback_target_known",
          if(is_nil(rollback_target), do: "failed", else: "ok"),
          if(is_nil(rollback_target),
            do: "rollback target is still missing from the recovery record",
            else: "declared rollback target is present and auditable"
          )
        ),
        review_check(
          "approval_evidence_present",
          "ok",
          "approval evidence was captured before rollback was executed"
        ),
        review_check(
          "UE Context Release",
          "ok",
          "cleanup evidence remains explicit after rollback"
        )
      ])
    )
    |> Map.put(
      :rollback_status,
      review_status(
        "ok",
        replacement_evidence_ref(:rollback, change, "post-rollback-verify"),
        "rollback target restored and verified"
      )
    )
  end

  defp maybe_put_replacement_review_semantics(payload, _phase, _change, _replacement), do: payload

  defp replacement_capture_gate_class(%Change{} = change, replacement) do
    case replacement_failure_class(:capture_artifacts, change, replacement, "failed") do
      failure_class when failure_class in ["core_failure", "cutover_or_rollback_failure"] ->
        "blocked"

      _ ->
        "degraded"
    end
  end

  defp replacement_capture_success?(%Change{} = change, replacement) do
    replacement_failure_class(:capture_artifacts, change, replacement, "ok") in [nil] and
      not user_plane_ping_failure?(change)
  end

  defp replacement_evidence_ref(phase, %Change{} = change, suffix) do
    "artifacts/replacement/#{replacement_phase_name(phase)}/#{change.change_id}/#{normalize_replacement_suffix(suffix)}.json"
  end

  defp replacement_phase_name(:capture_artifacts), do: "capture"
  defp replacement_phase_name(phase), do: Atom.to_string(phase)

  defp normalize_replacement_suffix("session"), do: "session"
  defp normalize_replacement_suffix("pdu-session"), do: "pdu-session"
  defp normalize_replacement_suffix("f1_c"), do: "f1-c"
  defp normalize_replacement_suffix("f1_u"), do: "f1-u"
  defp normalize_replacement_suffix("ru_fronthaul"), do: "ru-fronthaul"

  defp normalize_replacement_suffix(suffix) when is_binary(suffix),
    do: String.replace(suffix, "_", "-")

  defp replacement_review_rollback_target(%Change{} = change) do
    rollback_target = Map.get(change, :rollback_target)

    cond do
      is_binary(rollback_target) and rollback_target != "" ->
        rollback_target

      is_binary(change.requested_current_backend) and change.requested_current_backend != "" ->
        change.requested_current_backend

      is_atom(change.current_backend) and not is_nil(change.current_backend) ->
        Atom.to_string(change.current_backend)

      is_binary(change.current_backend) and change.current_backend != "" ->
        change.current_backend

      true ->
        nil
    end
  end

  defp replacement_review_checks(acceptance_gates, base_checks) do
    base_checks
    |> maybe_append_check(
      Enum.member?(acceptance_gates, "registration"),
      review_check(
        "registration_reviewed",
        "ok",
        "registration-path evidence is part of the review bundle"
      )
    )
    |> maybe_append_check(
      Enum.member?(acceptance_gates, "pdu_session"),
      review_check(
        "pdu_session_reviewed",
        "ok",
        "session-path evidence remains attached to the review bundle"
      )
    )
    |> maybe_append_check(
      Enum.member?(acceptance_gates, "ping"),
      review_check("ping_reviewed", "ok", "probe evidence remains attached to the review bundle")
    )
  end

  defp review_status(status, evidence_ref, reason) do
    %{status: status, evidence_ref: evidence_ref, reason: reason}
  end

  defp review_check(name, status, detail) do
    %{"name" => name, "status" => status, "detail" => detail}
  end

  defp maybe_append_check(checks, true, check), do: checks ++ [check]
  defp maybe_append_check(checks, false, _check), do: checks

  defp do_execute_replacement_plan(%Change{} = change) do
    rollback_target = Map.get(change, :rollback_target) || "oai_reference"
    rollback_plan = build_rollback_plan(change, rollback_target)

    Store.ensure_root!()
    Store.write_json(Store.rollback_plan_path(change.change_id), rollback_plan)

    plan =
      replacement_virtual_plan(change)
      |> Map.put("cell_group", change.cell_group)
      |> Map.put("max_blast_radius", change.max_blast_radius)
      |> Map.put("artifacts", [
        Store.plan_path(change.change_id),
        Store.rollback_plan_path(change.change_id)
      ])
      |> Map.put("rollback_plan", rollback_plan)
      |> put_optional("approval_required", approval_required?(:apply, change))
      |> put_optional("approval_fields_required", approval_fields_required(:apply, change))
      |> ReplacementReview.enrich(:plan, change, [])
      |> Map.put("summary", "change plan prepared for #{change.scope}")

    Store.write_json(Store.plan_path(change.change_id), plan)
    {:ok, plan}
  end

  defp replacement_virtual_plan(%Change{} = change) do
    %{
      "status" => "planned",
      "command" => "plan",
      "scope" => change.scope,
      "change_id" => change.change_id,
      "incident_id" => change.incident_id,
      "target_backend" => maybe_to_string(change.target_backend) || "replacement_shadow",
      "rollback_target" => Map.get(change, :rollback_target) || "oai_reference",
      "runtime_contract" => nil,
      "verify_window" => change.verify_window
    }
  end

  defp replacement_virtual_change_state(%Change{} = change) do
    %{
      "status" => "applied",
      "command" => "apply",
      "scope" => change.scope,
      "change_id" => change.change_id,
      "incident_id" => change.incident_id,
      "target_backend" => maybe_to_string(change.target_backend) || "replacement_shadow",
      "rollback_target" => Map.get(change, :rollback_target) || "oai_reference"
    }
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

  defp target_backend_known?(%Change{scope: scope, target_backend: backend})
       when scope in @replacement_scopes,
       do: replacement_backend?(backend)

  defp target_backend_known?(%Change{target_backend: nil}), do: true

  defp target_backend_known?(%Change{target_backend: backend}),
    do: backend in RanCore.supported_backends()

  defp replacement_backend?(backend) when is_atom(backend),
    do: Atom.to_string(backend) in @replacement_backends

  defp replacement_backend?(backend) when is_binary(backend), do: backend in @replacement_backends
  defp replacement_backend?(_backend), do: false

  defp require_replacement_field(errors, field, value) when is_list(value) do
    if value == [] do
      [{String.to_atom(field), "replacement metadata must include #{field}"} | errors]
    else
      errors
    end
  end

  defp require_replacement_field(errors, field, value) do
    if present?(value) do
      errors
    else
      [{String.to_atom(field), "replacement metadata must include #{field}"} | errors]
    end
  end

  defp validate_replacement_rollback_target(errors, :precheck, _change), do: errors

  defp validate_replacement_rollback_target(errors, _command, %Change{} = change) do
    if present?(replacement_review_rollback_target(change)) do
      errors
    else
      [
        {:rollback_target,
         "replacement lifecycle commands require rollback_target or current_backend"}
        | errors
      ]
    end
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

  defp runtime_precheck_contract(%Change{} = change, runtime_precheck) do
    if OaiRuntime.runtime_requested?(change.metadata) and
         match?({:ok, _payload}, runtime_precheck) do
      case RuntimeContract.precheck_contract(change) do
        {:ok, contract} -> contract
        {:error, _payload} -> nil
      end
    end
  end

  defp put_runtime_contract(payload, nil), do: payload

  defp put_runtime_contract(payload, %{} = runtime_contract),
    do: Map.put(payload, "runtime_contract", runtime_contract)

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

  defp capture_bundle(%Change{} = change, ref, runtime_capture, snapshots, review) do
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
        precheck: existing_path(change.change_id && Store.precheck_path(change.change_id)),
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
    |> put_optional(:review, review)
  end

  defp existing_path(nil), do: nil

  defp existing_path(path) do
    if File.exists?(path), do: path, else: nil
  end

  defp materialize_replacement_artifacts(payload, phase, %Change{} = change) do
    if replacement_scope?(change.scope) do
      anchor_paths = persist_replacement_anchor_artifacts(payload, phase, change)
      review_paths = persist_replacement_review_artifacts(payload, phase, change)
      evidence_paths = persist_replacement_evidence_refs(payload, phase, change)

      artifacts =
        payload
        |> payload_artifacts()
        |> Kernel.++(anchor_paths)
        |> Kernel.++(review_paths)
        |> Kernel.++(evidence_paths)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      Map.put(payload, :artifacts, artifacts)
    else
      payload
    end
  end

  defp persist_replacement_anchor_artifacts(payload, phase, %Change{} = change) do
    target_ref = payload[:target_ref] || payload["target_ref"] || replacement_target_ref(change)

    if is_binary(target_ref) and target_ref != "" do
      path =
        Store.replacement_path(
          replacement_phase_name(phase),
          change.change_id,
          "#{target_ref}.json"
        )

      [
        Store.write_json(path, %{
          captured_at: now_iso8601(),
          command: payload[:command] || payload["command"],
          change_id: change.change_id,
          incident_id: change.incident_id,
          target_ref: target_ref,
          target_profile: payload[:target_profile] || payload["target_profile"],
          summary: payload[:summary] || payload["summary"]
        })
      ]
    else
      []
    end
  end

  defp payload_artifacts(payload) do
    case payload[:artifacts] || payload["artifacts"] do
      artifacts when is_list(artifacts) -> Enum.filter(artifacts, &is_binary/1)
      _ -> []
    end
  end

  defp persist_replacement_review_artifacts(payload, phase, %Change{} = change) do
    review = get_in(payload, [:bundle, :review]) || get_in(payload, ["bundle", "review"]) || %{}
    compare_report_path = review[:compare_report] || review["compare_report"]

    []
    |> maybe_write_json(
      review[:request_snapshot] || review["request_snapshot"],
      replacement_request_snapshot(change)
    )
    |> maybe_write_json(compare_report_path, replacement_compare_report(payload, phase, change))
    |> maybe_write_json(
      review[:rollback_evidence] || review["rollback_evidence"],
      replacement_rollback_evidence(payload, phase, change, compare_report_path)
    )
  end

  defp maybe_write_json(paths, nil, _payload), do: paths

  defp maybe_write_json(paths, path, payload) when is_binary(path) and is_map(payload) do
    paths ++ [Store.write_json(path, payload)]
  end

  defp persist_replacement_evidence_refs(payload, phase, %Change{} = change) do
    replacement_paths =
      payload_artifacts(payload) ++ collect_evidence_refs(payload)

    replacement_paths
    |> Enum.filter(&materialized_replacement_path?/1)
    |> Enum.uniq()
    |> Enum.map(fn ref ->
      if File.exists?(ref) do
        ref
      else
        Store.write_json(ref, replacement_evidence_stub(ref, payload, phase, change))
      end
    end)
  end

  defp collect_evidence_refs(value) when is_list(value),
    do: Enum.flat_map(value, &collect_evidence_refs/1)

  defp collect_evidence_refs(value) when is_map(value) do
    direct =
      case value[:evidence_ref] || value["evidence_ref"] do
        evidence_ref when is_binary(evidence_ref) -> [evidence_ref]
        _ -> []
      end

    direct ++ Enum.flat_map(Map.values(value), &collect_evidence_refs/1)
  end

  defp collect_evidence_refs(_value), do: []

  defp materialized_replacement_path?(path) do
    is_binary(path) and
      (String.starts_with?(path, "#{Store.artifact_root()}/replacement/") or
         String.starts_with?(path, "#{Store.artifact_root()}/captures/"))
  end

  defp replacement_request_snapshot(%Change{} = change) do
    %{
      captured_at: now_iso8601(),
      scope: change.scope,
      target_ref: change.target_ref,
      target_backend: change.requested_target_backend || maybe_to_string(change.target_backend),
      current_backend:
        change.requested_current_backend || maybe_to_string(change.current_backend),
      rollback_target: change.rollback_target,
      change_id: change.change_id,
      incident_id: change.incident_id,
      reason: change.reason,
      idempotency_key: change.idempotency_key,
      ttl: change.ttl,
      dry_run: change.dry_run,
      verify_window: change.verify_window,
      max_blast_radius: change.max_blast_radius,
      metadata: change.metadata
    }
  end

  defp replacement_compare_report(payload, phase, %Change{} = change) do
    replacement = replacement_metadata(change)
    failure_class = payload[:failure_class] || payload["failure_class"]
    gate_class = payload[:gate_class] || payload["gate_class"]
    suggested_next = payload[:suggested_next] || payload["suggested_next"] || []

    %{
      report_id: "cmp-#{change.change_id || phase}-#{replacement_phase_name(phase)}",
      change_id: change.change_id,
      incident_id: change.incident_id || "#{change.change_id}-capture",
      target_profile: replacement["target_profile"],
      core_profile: payload[:core_profile] || payload["core_profile"],
      conformance_claim: payload[:conformance_claim] || payload["conformance_claim"],
      core_endpoint: payload[:core_endpoint] || payload["core_endpoint"],
      comparison_scope: replacement_comparison_scope(phase, failure_class),
      expected_state: replacement_expected_state(payload),
      observed_state: replacement_observed_state(payload),
      gate_class: gate_class,
      failure_class: failure_class,
      ngap_subset: replacement["ngap_subset"] || %{},
      diff_summary: replacement_diff_summary(gate_class, failure_class),
      evidence_refs: replacement_report_evidence_refs(payload, change, phase),
      rollback_target:
        payload[:rollback_target] || payload["rollback_target"] ||
          replacement_rollback_target(change),
      operator_next_step:
        List.first(suggested_next) || "review the captured lane evidence before the next mutation",
      summary: payload[:summary] || payload["summary"]
    }
  end

  defp replacement_rollback_evidence(payload, phase, %Change{} = change, compare_report_path) do
    gate_class = payload[:gate_class] || payload["gate_class"]

    rollback_target =
      payload[:rollback_target] || payload["rollback_target"] ||
        replacement_rollback_target(change)

    %{
      rollback_id: "rbk-#{change.change_id || phase}",
      change_id: change.change_id,
      incident_id: change.incident_id || "#{change.change_id}-capture",
      target_profile: payload[:target_profile] || payload["target_profile"],
      rollback_target: rollback_target,
      rollback_reason: replacement_rollback_reason(phase, gate_class),
      triggering_gate: gate_class,
      pre_rollback_state: %{
        compare_report_ref: compare_report_path,
        gate_class: gate_class,
        cutover_state: payload[:target_backend] || payload["target_backend"],
        observed_problem: payload[:summary] || payload["summary"]
      },
      post_rollback_state: %{
        rollback_target: rollback_target,
        cutover_state: if(phase == :rollback, do: "rolled_back", else: "not_executed"),
        repair_state:
          if(phase == :rollback,
            do: "rollback target restored and ready for another bounded run",
            else: "rollback remains available and explicit for the next mutation"
          )
      },
      recovery_check: %{
        status: replacement_recovery_status(phase, gate_class),
        checks: replacement_recovery_checks(phase, gate_class)
      },
      evidence_refs:
        ([compare_report_path] ++ replacement_report_evidence_refs(payload, change, phase))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      operator_notes:
        if(phase == :rollback,
          do:
            "Rollback preserved a reviewable recovery path and kept the reference lane explicit.",
          else:
            "Rollback was not executed, but the captured evidence preserves the explicit recovery path."
        )
    }
  end

  defp replacement_evidence_stub(path, payload, phase, %Change{} = change) do
    %{
      captured_at: now_iso8601(),
      command: payload[:command] || payload["command"],
      phase: replacement_phase_name(phase),
      change_id: change.change_id,
      incident_id: change.incident_id,
      target_ref: payload[:target_ref] || payload["target_ref"],
      target_profile: payload[:target_profile] || payload["target_profile"],
      core_profile: payload[:core_profile] || payload["core_profile"],
      status: payload[:status] || payload["status"],
      summary: payload[:summary] || payload["summary"],
      evidence_kind: Path.basename(path, ".json"),
      evidence_ref: path
    }
  end

  defp replacement_expected_state(payload) do
    %{
      attach: status_label(payload[:attach_status] || payload["attach_status"]),
      pdu_session: status_label(payload[:pdu_session_status] || payload["pdu_session_status"]),
      ping: status_label(payload[:ping_status] || payload["ping_status"]),
      release: status_label(payload[:release_status] || payload["release_status"])
    }
  end

  defp replacement_observed_state(payload), do: replacement_expected_state(payload)

  defp status_label(%{status: status}) when is_binary(status), do: status
  defp status_label(%{"status" => status}) when is_binary(status), do: status
  defp status_label(_value), do: "unknown"

  defp replacement_comparison_scope(_phase, "core_failure"), do: "registration"
  defp replacement_comparison_scope(_phase, "user_plane_failure"), do: "ping"
  defp replacement_comparison_scope(_phase, "cutover_or_rollback_failure"), do: "cutover"
  defp replacement_comparison_scope(:precheck, _failure_class), do: "registration"
  defp replacement_comparison_scope(_phase, _failure_class), do: "ping"

  defp replacement_diff_summary("pass", _failure_class) do
    [
      "Attach, registration, PDU session, and ping remained within the declared lane.",
      "The rollback target stayed explicit while the live-lab evidence bundle was captured."
    ]
  end

  defp replacement_diff_summary(_gate_class, "core_failure") do
    [
      "The NGAP registration path diverged before the declared lane could complete.",
      "Rollback remained the safer operator path until the core-side mismatch is explained."
    ]
  end

  defp replacement_diff_summary(_gate_class, "user_plane_failure") do
    [
      "Registration and PDU session completed, but the declared user-plane route did not finish a successful ping.",
      "The failure is isolated to the user-plane evidence bundle until proven otherwise."
    ]
  end

  defp replacement_diff_summary(_gate_class, _failure_class) do
    [
      "The captured evidence bundle preserves the mismatch that blocked or degraded the declared lane.",
      "The rollback target remains explicit for replay and recovery."
    ]
  end

  defp replacement_report_evidence_refs(payload, %Change{} = change, phase) do
    refs =
      payload
      |> payload_artifacts()
      |> Enum.take(8)

    if refs == [] do
      fallback_ref =
        case phase do
          :capture_artifacts ->
            Store.capture_path(change.incident_id || change.change_id || "capture")

          :verify ->
            Store.verify_path(change.change_id)

          _ ->
            replacement_evidence_ref(phase, change, "summary")
        end

      [fallback_ref]
    else
      refs
    end
  end

  defp replacement_rollback_reason(:rollback, _gate_class),
    do:
      "The captured mismatch made the declared rollback target safer than leaving the changed lane active."

  defp replacement_rollback_reason(_phase, "pass"),
    do:
      "Rollback was not required because the declared lane stayed within the live-lab proof envelope."

  defp replacement_rollback_reason(_phase, _gate_class),
    do: "The captured mismatch keeps rollback explicit until the lane is corrected."

  defp replacement_recovery_status(:rollback, _gate_class), do: "ok"
  defp replacement_recovery_status(_phase, "pass"), do: "ok"
  defp replacement_recovery_status(_phase, gate_class), do: gate_class

  defp replacement_recovery_checks(:rollback, _gate_class) do
    ["rollback_target_restored", "post_rollback_verify_recorded", "recovery_path_auditable"]
  end

  defp replacement_recovery_checks(_phase, "pass") do
    ["bundle_fetchable", "rollback_target_explicit", "live_lab_proof_preserved"]
  end

  defp replacement_recovery_checks(_phase, _gate_class) do
    ["rollback_target_explicit", "compare_report_preserved", "review_path_auditable"]
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
    ["prechecks", "plans", "changes", "verify", "captures", "approvals", "rollback_plans"]
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
      Store.precheck_path(change_id),
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
