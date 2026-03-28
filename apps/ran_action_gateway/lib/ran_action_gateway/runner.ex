defmodule RanActionGateway.Runner do
  @moduledoc """
  Deterministic action runner for the bootstrap `ranctl` contract.
  """

  require Logger

  alias RanActionGateway.ArtifactRetention
  alias RanActionGateway.Change
  alias RanActionGateway.ControlState
  alias RanActionGateway.OaiSimulation
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
  @ru_failure_hints [
    "failed ru sync",
    "failed-ru-sync",
    "failed_ru_sync",
    "ru sync failed",
    "ru-sync failed",
    "ru_sync_failed"
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
    simulation_precheck = simulation_precheck(change)
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
        operational_checks(change, control_state) ++
        runtime_checks(runtime_precheck) ++ simulation_checks(simulation_precheck)

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
      |> put_oai_simulation_result(simulation_precheck, change)
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
         {:ok, runtime_verify} <- maybe_verify_runtime(change),
         {:ok, simulation_verify} <- maybe_verify_oai_simulation(change) do
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
        |> Kernel.++(simulation_checks({:ok, simulation_verify}))

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
        |> put_oai_simulation_result({:ok, simulation_verify}, change)
        |> maybe_put_replacement_status(:verify, change, checks)
        |> maybe_put_oai_simulation_semantics(:verify, change)
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
          restored_from: replacement_restore_source(change) || plan["target_backend"],
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
       |> maybe_add_observe_artifact(change)
       |> maybe_put_replacement_status(:observe, change, [])
       |> materialize_replacement_artifacts(:observe, change)
       |> persist_observe(change)}
    end
  end

  defp do_execute(:capture_artifacts, change) do
    ref = change.incident_id || change.change_id || "ad-hoc-capture"

    with {:ok, runtime_capture} <- maybe_capture_runtime(change),
         {:ok, simulation_capture} <- maybe_capture_oai_simulation(change) do
      snapshots = capture_supporting_snapshots(change, ref)
      review = ReplacementReview.capture_review(change, ref)
      bundle = capture_bundle(change, ref, runtime_capture, simulation_capture, snapshots, review)

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
        |> put_oai_simulation_result({:ok, simulation_capture}, change)
        |> maybe_put_replacement_status(:capture_artifacts, change, [])
        |> maybe_put_oai_simulation_semantics(:capture_artifacts, change)
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

  defp maybe_add_observe_artifact(payload, %Change{} = change) do
    case observe_ref(change) do
      ref when is_binary(ref) ->
        Map.put(payload, :artifacts, [Store.observation_path(ref)])

      _ ->
        payload
    end
  end

  defp persist_observe(payload, %Change{} = change) do
    case observe_ref(change) do
      ref when is_binary(ref) ->
        Store.write_json(Store.observation_path(ref), payload)
        payload

      _ ->
        payload
    end
  end

  defp observe_ref(%Change{change_id: change_id, incident_id: incident_id}) do
    change_id || incident_id
  end

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
          do: {:ok, replacement_virtual_plan_for_rollback(change)},
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
      |> Map.put(:protocol_claims, replacement_protocol_claims(change))
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
      |> maybe_put_ru_interface_semantics(phase, change)
      |> maybe_put_rollback_status(phase, change, base_status)
      |> maybe_put_user_plane_semantics(phase, change, replacement)
      |> maybe_put_control_plane_interface_semantics(phase, change)
      |> maybe_put_attach_status(phase, change, replacement, base_status)
      |> maybe_put_session_gate_statuses(phase, change, replacement)
      |> maybe_put_replacement_review_semantics(phase, change, replacement)
      |> maybe_put_target_host_precheck_semantics(phase, change, replacement)
      |> maybe_put_declared_replacement_artifacts(phase, change)
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

  defp maybe_put_target_host_precheck_semantics(
         payload,
         :precheck,
         %Change{scope: "target_host"} = change,
         replacement
       ) do
    profile = replacement_target_profile_contract(change)
    overlay = replacement_target_profile_overlay(change)
    core_profile = replacement["open5gs_core"] || %{}
    target_backend = replacement_target_backend(:precheck, change)
    rollback_target = replacement_rollback_target(change)

    layout =
      get_in(overlay, ["target_host", "deployment_layout"]) ||
        get_in(profile, ["host_boundary", "deployment_layout"])

    host_evidence = get_in(profile, ["host_boundary", "preflight_evidence_ref"])
    ru_evidence = get_in(profile, ["ru_boundary", "readiness_evidence_ref"])

    core_evidence =
      get_in(profile, ["core_boundary", "registration_evidence_ref"]) ||
        replacement_evidence_ref(:precheck, change, "core-link")

    host_resources = get_in(replacement, ["native_probe", "required_resources"]) || []

    status = if(layout && rollback_target, do: "blocked", else: "failed")

    payload
    |> Map.put(:status, status)
    |> Map.put(
      :summary,
      "Target-host precheck is blocked because the declared timing, layout, and fronthaul dependencies are not yet proven."
    )
    |> Map.put(:gate_class, "blocked")
    |> put_optional(:target_backend, target_backend)
    |> put_optional(:rollback_target, rollback_target)
    |> Map.put(:rollback_available, not is_nil(rollback_target))
    |> Map.put(:approval_required, false)
    |> Map.put(:core_profile, core_profile["profile"] || replacement["core_profile"])
    |> Map.put(
      :conformance_claim,
      %{
        profile: @baseline_conformance_profile,
        evidence_tier: "standards_subset",
        baseline_ref: @baseline_conformance_ref
      }
    )
    |> Map.put(
      :core_endpoint,
      %{
        profile: core_profile["profile"] || replacement["core_profile"],
        release_ref: get_in(profile, ["core_boundary", "release_ref"]),
        n2: get_in(core_profile, ["n2"]),
        n3: get_in(core_profile, ["n3"])
      }
    )
    |> Map.put(
      :checks,
      [
        %{
          "name" => "host_preflight",
          "status" => "blocked",
          "detail" =>
            "host readiness is not yet proven for #{Enum.join(host_resources, ", ")} and layout #{layout || "unknown"}"
        },
        %{
          "name" => "ru_sync",
          "status" => "blocked",
          "detail" => "RU sync has not been demonstrated for the declared profile"
        },
        %{
          "name" => "core_link_reachable",
          "status" => if(core_profile["profile"], do: "ok", else: "blocked"),
          "detail" =>
            if(core_profile["profile"],
              do:
                "Open5GS endpoint #{get_in(core_profile, ["n2", "amf_host"])}:#{get_in(core_profile, ["n2", "amf_port"])} for profile #{core_profile["profile"]} is declared and reachable from the target profile",
              else: "the declared Open5GS core profile is still missing"
            )
        }
      ]
    )
    |> Map.put(
      :plane_status,
      %{
        s_plane: %{
          status: "blocked",
          evidence_ref: replacement_evidence_ref(:precheck, change, "ptp-state"),
          reason: "timing source is not yet proven for the declared lane"
        },
        m_plane: %{
          status: if(layout, do: "ok", else: "blocked"),
          evidence_ref: replacement_evidence_ref(:precheck, change, "host-inventory"),
          reason:
            if(layout, do: nil, else: "deployment layout is missing from the declared profile")
        },
        c_plane: %{
          status: "blocked",
          evidence_ref: replacement_evidence_ref(:precheck, change, "core-link"),
          reason: "cutover to the replacement lane is not yet allowed"
        },
        u_plane: %{
          status: "blocked",
          evidence_ref: replacement_evidence_ref(:precheck, change, "user-plane"),
          reason: "user-plane path is not yet declared ready"
        }
      }
    )
    |> Map.put(
      :ru_status,
      %{
        status: "blocked",
        evidence_ref: replacement_evidence_ref(:precheck, change, "ru-sync"),
        reason: "RU sync has not been confirmed"
      }
    )
    |> Map.put(
      :core_link_status,
      %{
        status: "ok",
        evidence_ref: core_evidence,
        reason: nil,
        profile: core_profile["profile"] || replacement["core_profile"]
      }
    )
    |> Map.put(:failure_class, "ru_failure")
    |> put_optional(:ngap_subset, replacement["ngap_subset"])
    |> Map.put(
      :artifacts,
      Enum.reject(
        [
          List.first(payload[:artifacts] || []),
          host_evidence || replacement_evidence_ref(:precheck, change, "host-inventory"),
          ru_evidence || replacement_evidence_ref(:precheck, change, "ru-sync"),
          core_evidence
        ],
        &is_nil/1
      )
    )
    |> Map.put(
      :suggested_next,
      [
        "inspect host timing and RU link blockers",
        "confirm rollback target remains known",
        "rerun precheck after RF and sync assumptions are corrected"
      ]
    )
  end

  defp maybe_put_target_host_precheck_semantics(payload, _phase, _change, _replacement),
    do: payload

  defp replacement_target_profile_contract(%Change{} = change) do
    case change |> replacement_metadata() |> Map.get("target_profile") do
      nil -> %{}
      profile -> load_replacement_profile_json(profile, ".example.json")
    end
  end

  defp replacement_target_profile_overlay(%Change{} = change) do
    case change |> replacement_metadata() |> Map.get("target_profile") do
      nil -> %{}
      profile -> load_replacement_profile_json(profile, ".lab-owner-overlay.example.json")
    end
  end

  defp load_replacement_profile_json(profile_name, suffix) do
    repo_root = Path.expand("../../../../", __DIR__)

    path =
      Path.join(repo_root, "subprojects/ran_replacement/contracts/examples/*#{suffix}")
      |> Path.wildcard()
      |> Enum.find(fn candidate ->
        case File.read(candidate) do
          {:ok, body} ->
            case JSON.decode(body) do
              {:ok, payload} -> payload["profile"] == profile_name
              _ -> false
            end

          _ ->
            false
        end
      end)

    with path when is_binary(path) <- path,
         {:ok, body} <- File.read(path),
         {:ok, payload} <- JSON.decode(body) do
      payload
    else
      _ -> %{}
    end
  end

  defp replacement_protocol_claims(%Change{} = change) do
    profile = replacement_target_profile_contract(change)
    claims = profile["standards_subset"] || %{}

    ngap_subset =
      replacement_metadata(change)["ngap_subset"] || Map.get(claims, "ngap") || %{}

    if claims == %{} do
      if ngap_subset == %{}, do: %{}, else: %{"ngap" => ngap_subset}
    else
      Map.put(claims, "ngap", ngap_subset)
    end
  end

  defp replacement_declared_evidence_refs(%Change{} = change) do
    profile = replacement_target_profile_contract(change)
    overlay = replacement_target_profile_overlay(change)

    %{
      attach:
        get_in(overlay, ["ue_inventory", "attach_artifact"]) ||
          get_in(profile, ["ue_boundary", "attach_evidence_ref"]),
      registration:
        replacement_overlay_artifact(
          overlay,
          ["core_inventory", "artifacts"],
          "registration.json"
        ) ||
          get_in(profile, ["core_boundary", "registration_evidence_ref"]),
      pdu_session:
        replacement_overlay_artifact(overlay, ["core_inventory", "artifacts"], "pdu-session.json") ||
          get_in(profile, ["core_boundary", "pdu_session_evidence_ref"]),
      ping:
        get_in(overlay, ["ue_inventory", "ping_artifact"]) ||
          get_in(profile, ["ue_boundary", "ping_evidence_ref"]),
      preflight: get_in(profile, ["host_boundary", "preflight_evidence_ref"]),
      ru_readiness:
        replacement_overlay_artifact(
          overlay,
          ["ru_inventory", "readiness_artifacts"],
          "ru-readiness.json"
        ) ||
          get_in(profile, ["ru_boundary", "readiness_evidence_ref"]),
      ptp:
        replacement_overlay_artifact(overlay, ["ru_inventory", "readiness_artifacts"], "ptp.json"),
      rollback: get_in(profile, ["evidence_paths", "rollback_evidence_ref"])
    }
  end

  defp replacement_overlay_artifact(overlay, path, suffix) do
    overlay
    |> get_in(path)
    |> List.wrap()
    |> Enum.find(fn value -> is_binary(value) and String.ends_with?(value, suffix) end)
  end

  defp replacement_declared_evidence_ref(%Change{} = change, key, phase, fallback_suffix) do
    case replacement_declared_evidence_refs(change)[key] do
      value when is_binary(value) and value != "" -> value
      _ -> replacement_evidence_ref(phase, change, fallback_suffix)
    end
  end

  defp replacement_gate_class(:precheck, "failed"), do: "blocked"
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

      phase == :observe and ru_sync_failure?(change) ->
        "RU sync is degraded; the lane is visible, but the declared sync target is not stable enough for attach."

      phase == :capture_artifacts and ru_sync_failure?(change) ->
        "Capture preserved the RU failure evidence bundle for rollback review on the declared lane."

      phase == :observe and user_plane_ping_failure?(change) ->
        "User-plane observe confirms attach and session hold, but ping diverged on the declared route."

      phase == :capture_artifacts and user_plane_ping_failure?(change) ->
        "Capture preserved the user-plane evidence bundle after ping failed on the declared route."

      phase == :observe and control_plane_scope?(change) ->
        "Control-plane replacement observe confirms that F1-C release and re-establishment guardrails plus E1AP bearer release, re-establishment, and bounded handover-adjacent refresh diverged from the planned cutover lane."

      true ->
        "#{phase |> Atom.to_string()} replacement #{target_role} status is #{status}"
    end
  end

  defp replacement_core_link_status(phase, %Change{} = change, replacement, status) do
    core = replacement["open5gs_core"] || %{}
    profile = core["profile"] || replacement["core_profile"]
    ngap_failure? = ngap_registration_failure?(change)

    %{
      status: replacement_core_link_state(status, ngap_failure?),
      evidence_ref: replacement_declared_evidence_ref(change, :registration, phase, "core-link"),
      reason: replacement_core_link_reason(status, ngap_failure?),
      profile: profile
    }
  end

  defp replacement_core_link_state(_status, true), do: "failed"
  defp replacement_core_link_state("failed", _ngap_failure?), do: "failed"
  defp replacement_core_link_state(_status, _ngap_failure?), do: "ok"

  defp replacement_core_link_reason(_status, true),
    do: "the real Open5GS core rejected the declared subscriber or identity context"

  defp replacement_core_link_reason("failed", _ngap_failure?),
    do: "replacement control surface has not yet proven the real Open5GS core path"

  defp replacement_core_link_reason(_status, _ngap_failure?), do: nil

  defp replacement_interface_status(phase, %Change{} = change, replacement, status) do
    ngap_failure? = ngap_registration_failure?(change)
    ping_failure? = user_plane_ping_failure?(change)

    replacement
    |> Map.get("required_interfaces", [])
    |> Enum.map(fn interface ->
      {interface,
       %{
         status: replacement_interface_state(interface, status, ngap_failure?),
         evidence_ref:
           replacement_interface_evidence_ref(
             interface,
             phase,
             change,
             ngap_failure?,
             ping_failure?
           ),
         reason: replacement_interface_reason(interface, status, ngap_failure?)
       }}
    end)
    |> Enum.into(%{})
  end

  defp replacement_interface_state("ngap", _status, true), do: "failed"

  defp replacement_interface_state(interface, _status, true) when interface in ["f1_u", "gtpu"],
    do: "pending"

  defp replacement_interface_state(_interface, "failed", _ngap_failure?), do: "pending"
  defp replacement_interface_state(_interface, _status, _ngap_failure?), do: "ok"

  defp replacement_interface_reason("ngap", _status, true),
    do: "the last observed NGAP procedure ended in registration rejection"

  defp replacement_interface_reason("f1_u", _status, true), do: "user-plane was not exercised"

  defp replacement_interface_reason("gtpu", _status, true),
    do: "session establishment and ping were not reached"

  defp replacement_interface_reason(_interface, "failed", _ngap_failure?),
    do: "replacement evidence for this interface is not yet fully surfaced by the control surface"

  defp replacement_interface_reason(_interface, _status, _ngap_failure?), do: nil

  defp replacement_interface_evidence_ref(
         "ngap",
         phase,
         %Change{} = change,
         _ngap_failure?,
         _ping_failure?
       ),
       do: replacement_declared_evidence_ref(change, :registration, phase, "ngap")

  defp replacement_interface_evidence_ref(
         "f1_u",
         phase,
         %Change{} = change,
         ngap_failure?,
         ping_failure?
       ),
       do:
         replacement_user_plane_interface_ref(change, phase, ngap_failure?, ping_failure?, "f1_u")

  defp replacement_interface_evidence_ref(
         "gtpu",
         phase,
         %Change{} = change,
         ngap_failure?,
         ping_failure?
       ),
       do:
         replacement_user_plane_interface_ref(change, phase, ngap_failure?, ping_failure?, "gtpu")

  defp replacement_interface_evidence_ref(
         "ru_fronthaul",
         phase,
         %Change{} = change,
         _ngap_failure?,
         _ping_failure?
       ),
       do: replacement_declared_evidence_ref(change, :ru_readiness, phase, "ru-fronthaul")

  defp replacement_interface_evidence_ref(
         "ptp",
         phase,
         %Change{} = change,
         _ngap_failure?,
         _ping_failure?
       ) do
    refs = replacement_declared_evidence_refs(change)
    refs.ptp || refs.preflight || replacement_evidence_ref(phase, change, "ptp")
  end

  defp replacement_interface_evidence_ref(
         interface,
         phase,
         %Change{} = change,
         _ngap_failure?,
         _ping_failure?
       ),
       do: replacement_evidence_ref(phase, change, interface)

  defp replacement_user_plane_interface_ref(
         %Change{} = change,
         phase,
         ngap_failure?,
         ping_failure?,
         suffix
       ) do
    key =
      cond do
        ngap_failure? -> :pdu_session
        ping_failure? -> :ping
        true -> :pdu_session
      end

    replacement_declared_evidence_ref(change, key, phase, suffix)
  end

  defp maybe_put_ngap_procedure_trace(payload, phase, %Change{} = change, replacement, status) do
    if ngap_scope?(replacement) do
      procedures = replacement_ngap_procedures(phase, change, status)

      Map.put(payload, :ngap_procedure_trace, %{
        last_observed: replacement_ngap_last_observed(phase, procedures),
        procedures: procedures
      })
    else
      payload
    end
  end

  defp maybe_put_release_status(payload, phase, %Change{} = change, replacement, _status) do
    if ngap_scope?(replacement) do
      Map.put(payload, :release_status, %{
        status: "ok",
        evidence_ref:
          replacement_declared_evidence_ref(change, :registration, phase, "ue-context-release"),
        reason: nil
      })
    else
      payload
    end
  end

  defp maybe_put_ru_status(payload, phase, %Change{} = change, replacement, status) do
    if Enum.member?(replacement["acceptance_gates"] || [], "ru_sync") do
      blocked? = ru_sync_failure?(change) or status == "blocked"

      Map.put(payload, :ru_status, %{
        status: if(blocked?, do: "blocked", else: "ok"),
        evidence_ref: replacement_evidence_ref(phase, change, "ru-sync"),
        reason:
          if(blocked?,
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
      ru_sync_failure?(change) ->
        "ru_failure"

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
       replacement_declared_evidence_ref(change, :registration, phase, "ngap-setup"),
       replacement_ngap_detail(:ng_setup, status)},
      {"Initial UE Message", replacement_ngap_status(:initial_ue_message, status, ngap_failure?),
       replacement_declared_evidence_ref(change, :registration, phase, "initial-ue-message"),
       replacement_ngap_detail(:initial_ue_message, status)},
      {"Uplink NAS Transport",
       replacement_ngap_status(:uplink_nas_transport, status, ngap_failure?),
       replacement_declared_evidence_ref(change, :registration, phase, "uplink-nas-transport"),
       replacement_ngap_detail(:uplink_nas_transport, status)},
      {"Downlink NAS Transport",
       replacement_ngap_status(:downlink_nas_transport, status, ngap_failure?),
       replacement_declared_evidence_ref(change, :registration, phase, "downlink-nas-transport"),
       replacement_ngap_detail(:downlink_nas_transport, status)},
      {"UE Context Release", replacement_ngap_status(:ue_context_release, status, ngap_failure?),
       replacement_declared_evidence_ref(change, :registration, phase, "ue-context-release"),
       replacement_ngap_detail(:ue_context_release, status)}
    ]
    |> Kernel.++(replacement_ngap_bounded_claims(phase, change))
    |> Enum.map(fn {name, proc_status, evidence_ref, detail} ->
      %{name: name, status: proc_status, evidence_ref: evidence_ref, detail: detail}
    end)
  end

  defp replacement_ngap_last_observed(:rollback, procedures) do
    if Enum.any?(procedures, &(&1.name == "Reset" and &1.status == "ok")) do
      "Reset"
    else
      "UE Context Release"
    end
  end

  defp replacement_ngap_last_observed(_phase, _procedures), do: "UE Context Release"

  defp replacement_ngap_bounded_claims(phase, %Change{} = change) do
    error_indication =
      if phase in [:observe, :capture_artifacts] and ngap_registration_failure?(change) do
        [
          {"Error Indication", "ok", replacement_evidence_ref(phase, change, "error-indication"),
           "bounded recovery claim preserved a peer-visible NGAP error indication after the declared core rejection"}
        ]
      else
        []
      end

    reset =
      cond do
        change.scope == "replacement_cutover" and phase == :rollback ->
          [
            {"Reset", "ok", replacement_evidence_ref(:rollback, change, "reset"),
             "bounded recovery claim preserved an operator-approved NG reset before the rollback target was declared restored"}
          ]

        change.scope == "replacement_cutover" and phase in [:observe, :capture_artifacts] ->
          [
            {"Reset", "pending", replacement_evidence_ref(phase, change, "reset"),
             "bounded recovery claim stays explicit for the cutover rollback lane, but reset has not been executed yet"}
          ]

        true ->
          []
      end

    error_indication ++ reset
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
    cond do
      phase in [:observe, :capture_artifacts] and ru_sync_failure?(change) ->
        Map.put(payload, :plane_status, %{
          s_plane: %{
            status: "degraded",
            evidence_ref: replacement_evidence_ref(phase, change, "ptp-state"),
            reason: "timing source is visible but not stable"
          },
          m_plane: %{
            status: "ok",
            evidence_ref: replacement_evidence_ref(phase, change, "host-state"),
            reason: nil
          },
          c_plane: %{
            status: "degraded",
            evidence_ref: replacement_evidence_ref(phase, change, "control-plane"),
            reason: "control-plane stays shadow-only until RU sync stabilizes"
          },
          u_plane: %{
            status: "blocked",
            evidence_ref: replacement_evidence_ref(phase, change, "user-plane"),
            reason: "user-plane must not be trusted before RU sync stabilizes"
          }
        })

      phase == :observe and control_plane_scope?(change) ->
        Map.put(payload, :plane_status, %{
          c_plane: %{
            status: control_plane_observe_status(change, status),
            evidence_ref: replacement_evidence_ref(:observe, change, "cutover-control-plane"),
            reason: control_plane_observe_reason(change, status)
          }
        })

      true ->
        payload
    end
  end

  defp maybe_put_ru_interface_semantics(payload, phase, %Change{} = change)
       when phase in [:observe, :capture_artifacts] do
    if ru_sync_failure?(change) do
      update_in(payload, [:interface_status], fn interface_status ->
        interface_status
        |> maybe_put_user_plane_interface("ru_fronthaul", %{
          status: "blocked",
          evidence_ref: replacement_evidence_ref(phase, change, "ru-fronthaul"),
          reason: "stable RU sync is not yet proven on the declared fronthaul path"
        })
        |> maybe_put_user_plane_interface("ptp", %{
          status: "degraded",
          evidence_ref: replacement_evidence_ref(phase, change, "ptp"),
          reason: "timing source is visible but not stable enough for attach"
        })
      end)
    else
      payload
    end
  end

  defp maybe_put_ru_interface_semantics(payload, _phase, _change), do: payload

  defp maybe_put_rollback_status(payload, phase, %Change{} = change, status) do
    if phase == :observe and control_plane_scope?(change) do
      Map.put(payload, :rollback_status, %{
        status:
          if(control_plane_cutover_review?(change) or status == "failed",
            do: "pending",
            else: "ok"
          ),
        evidence_ref:
          replacement_declared_evidence_ref(change, :rollback, :observe, "rollback-evidence"),
        reason:
          if(control_plane_cutover_review?(change) or status == "failed",
            do:
              "rollback is available while F1-C/E1AP release and re-establishment remain under review",
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
          reason:
            "UE-context release, re-establishment guardrails, or single-lane handover-adjacent refresh diverged from the planned F1-C lane"
        })
        |> maybe_put_control_plane_interface("e1ap", %{
          status: "degraded",
          evidence_ref: replacement_evidence_ref(:observe, change, "e1ap"),
          reason:
            "bearer release, re-establishment, or single-lane handover-adjacent refresh diverged from the compare report"
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
        "control-plane release and re-establishment state is partially healthy but not ready for leave-running"

      status == "failed" ->
        "control-plane release, re-establishment, or coordination diverged from the planned lane"

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
    ngap_failure? = ngap_registration_failure?(change)

    user_plane =
      cond do
        ngap_failure? ->
          %{
            status: "blocked",
            evidence_ref:
              replacement_declared_evidence_ref(change, :registration, phase, "user-plane"),
            reason: "user-plane was not reached after the control-plane rejection"
          }

        phase == :verify and not user_plane_ping_failure?(change) ->
          %{
            status: "ok",
            evidence_ref: replacement_declared_evidence_ref(change, :ping, :verify, "user-plane"),
            reason: nil
          }

        user_plane_ping_failure?(change) and phase == :observe ->
          %{
            status: "degraded",
            evidence_ref:
              replacement_declared_evidence_ref(change, :ping, :observe, "user-plane"),
            reason: "user-plane confidence is incomplete after ping failed on the declared route"
          }

        user_plane_ping_failure?(change) and phase == :capture_artifacts ->
          %{
            status: "degraded",
            evidence_ref:
              replacement_declared_evidence_ref(change, :ping, :capture_artifacts, "user-plane"),
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
    ngap_failure? = ngap_registration_failure?(change)
    ping_failure? = user_plane_ping_failure?(change)

    Map.put(payload, :session_status, %{
      status:
        cond do
          ngap_failure? -> "pending"
          ping_failure? -> "established_but_ping_failed"
          true -> "established"
        end,
      pdu_type: session_profile["pdu_type"],
      ping_target: session_profile["expect_ping_target"],
      evidence_ref: replacement_evidence_ref(phase, change, "session"),
      reason:
        cond do
          ngap_failure? ->
            "session setup not reached after the NGAP rejection"

          ping_failure? ->
            "PDU session is established, but the declared route did not complete a successful ping"

          true ->
            nil
        end
    })
  end

  defp maybe_put_session_status(payload, _phase, _change, _replacement),
    do: payload

  defp maybe_put_user_plane_interfaces(payload, phase, %Change{} = change)
       when phase in [:verify, :observe, :capture_artifacts] do
    interface_status = Map.get(payload, :interface_status, %{})
    ngap_failure? = ngap_registration_failure?(change)

    {f1_u, gtpu} =
      cond do
        ngap_failure? ->
          {
            %{
              status: "pending",
              evidence_ref:
                replacement_declared_evidence_ref(change, :pdu_session, phase, "f1_u"),
              reason: "user-plane was not exercised"
            },
            %{
              status: "pending",
              evidence_ref:
                replacement_declared_evidence_ref(change, :pdu_session, phase, "gtpu"),
              reason: "session establishment and ping were not reached"
            }
          }

        phase == :verify and not user_plane_ping_failure?(change) ->
          {
            %{
              status: "ok",
              evidence_ref:
                replacement_declared_evidence_ref(change, :pdu_session, :verify, "f1_u"),
              reason: nil
            },
            %{
              status: "ok",
              evidence_ref:
                replacement_declared_evidence_ref(change, :pdu_session, :verify, "gtpu"),
              reason: nil
            }
          }

        user_plane_ping_failure?(change) ->
          {
            %{
              status: "degraded",
              evidence_ref: replacement_declared_evidence_ref(change, :ping, phase, "f1_u"),
              reason: "forwarding state does not yet prove the declared attach-plus-ping path"
            },
            %{
              status: "degraded",
              evidence_ref: replacement_declared_evidence_ref(change, :ping, phase, "gtpu"),
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
        evidence_ref:
          replacement_declared_evidence_ref(change, :rollback, :observe, "rollback-evidence"),
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

  defp ru_sync_failure?(%Change{verify_window: %{"checks" => checks}} = change)
       when is_list(checks),
       do: Enum.member?(checks, "ru_sync_failed") or ru_sync_failure_signal?(change)

  defp ru_sync_failure?(%Change{verify_window: %{checks: checks}} = change) when is_list(checks),
    do: Enum.member?(checks, "ru_sync_failed") or ru_sync_failure_signal?(change)

  defp ru_sync_failure?(%Change{} = change) do
    ru_sync_failure_signal?(change)
  end

  defp ru_sync_failure?(_change), do: false

  defp ru_sync_failure_signal?(%Change{} = change) do
    signal =
      [change.reason, change.incident_id, Enum.join(requested_check_names(change), " ")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    change.scope == "ru_link" or Enum.any?(@ru_failure_hints, &String.contains?(signal, &1))
  end

  defp maybe_put_attach_status(payload, phase, %Change{} = change, replacement, status) do
    if Enum.member?(replacement["acceptance_gates"] || [], "registration") do
      ngap_failure? = ngap_registration_failure?(change)

      Map.put(payload, :attach_status, %{
        status:
          cond do
            ngap_failure? -> "failed"
            status == "failed" -> "pending"
            true -> "ok"
          end,
        evidence_ref: replacement_declared_evidence_ref(change, :attach, phase, "attach"),
        reason:
          cond do
            ngap_failure? -> "attach did not progress beyond the NGAP registration stage"
            status == "failed" -> "replacement attach path is not yet fully proven"
            true -> nil
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
      session_profile = get_in(replacement, ["open5gs_core", "session_profile"]) || %{}
      ngap_failure? = ngap_registration_failure?(change)
      ping_failure? = user_plane_ping_failure?(change)

      Map.put(payload, :pdu_session_status, %{
        status: if(ngap_failure?, do: "pending", else: "ok"),
        evidence_ref:
          replacement_declared_evidence_ref(change, :pdu_session, phase, "pdu-session"),
        reason:
          cond do
            ngap_failure? ->
              "session setup not reached after the NGAP rejection"

            ping_failure? ->
              "PDU session is established, but the declared route did not complete a successful ping"

            is_binary(session_profile["pdu_type"]) ->
              "declared #{session_profile["pdu_type"]} session is established"

            true ->
              nil
          end
      })
    else
      payload
    end
  end

  defp maybe_put_ping_status(payload, phase, %Change{} = change, replacement) do
    if Enum.member?(replacement["acceptance_gates"] || [], "ping") do
      session_profile = get_in(replacement, ["open5gs_core", "session_profile"]) || %{}
      ngap_failure? = ngap_registration_failure?(change)
      ping_failure? = user_plane_ping_failure?(change)

      Map.put(payload, :ping_status, %{
        status:
          cond do
            ngap_failure? -> "pending"
            ping_failure? -> "failed"
            true -> "ok"
          end,
        evidence_ref: replacement_declared_evidence_ref(change, :ping, phase, "ping"),
        reason:
          cond do
            ngap_failure? ->
              "ping not attempted after the attach failure"

            ping_failure? ->
              "the declared ping target #{session_profile["expect_ping_target"] || "unknown"} did not answer"

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
          replacement_declared_evidence_ref(
            change,
            :rollback,
            :capture_artifacts,
            "rollback-evidence"
          ),
          "rollback target remains available but was not executed for this successful capture"
        )
      )
    else
      payload
      |> Map.put(
        :summary,
        cond do
          ru_sync_failure?(change) ->
            "Capture preserved the RU failure evidence bundle for rollback review on the declared lane."

          user_plane_ping_failure?(change) ->
            "Capture preserved the user-plane evidence bundle after ping failed on the declared route."

          true ->
            "Capture preserved the failed replacement evidence bundle for rollback review, including explicit F1-C/E1AP release, re-establishment, and bounded handover-adjacent refresh semantics."
        end
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
          ),
          review_check(
            "F1-C re-establishment guard",
            "ok",
            "F1-C cleanup and retry semantics remain explicit in the preserved review bundle"
          ),
          review_check(
            "E1AP bearer re-establishment",
            "ok",
            "E1AP bearer recovery semantics remain explicit in the preserved review bundle"
          ),
          review_check(
            "handover_adjacent_refresh_bounded",
            "ok",
            "the preserved bundle keeps the first handover-adjacent refresh bounded to the declared single-lane profile"
          )
        ])
      )
      |> Map.put(
        :rollback_status,
        review_status(
          "pending",
          replacement_declared_evidence_ref(
            change,
            :rollback,
            :capture_artifacts,
            "rollback-evidence"
          ),
          "rollback is available while F1-C/E1AP release and re-establishment remain under review"
        )
      )
    end
  end

  defp maybe_put_replacement_review_semantics(payload, :rollback, %Change{} = change, replacement) do
    rollback_target = replacement_review_rollback_target(change)
    target_role = replacement["target_role"] || change.scope

    restored_from =
      payload[:restored_from] || payload["restored_from"] || replacement_restore_source(change)

    payload
    |> Map.put(
      :summary,
      rollback_summary(target_role, restored_from, rollback_target)
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
        ),
        review_check(
          "F1-C re-establishment guard",
          "ok",
          "F1-C cleanup and retry semantics remain explicit after rollback"
        ),
        review_check(
          "E1AP bearer re-establishment",
          "ok",
          "E1AP bearer recovery semantics remain explicit after rollback"
        ),
        review_check(
          "handover_adjacent_refresh_bounded",
          "ok",
          "the bounded handover-adjacent refresh stays explicit without implying mobility transfer"
        )
      ])
    )
    |> Map.put(
      :rollback_status,
      review_status(
        "ok",
        replacement_declared_evidence_ref(change, :rollback, :rollback, "post-rollback-verify"),
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
      Enum.member?(acceptance_gates, "host_preflight"),
      review_check(
        "host_preflight_reviewed",
        "ok",
        "host readiness evidence is part of the review bundle"
      )
    )
    |> maybe_append_check(
      Enum.member?(acceptance_gates, "ru_sync"),
      review_check(
        "ru_sync_reviewed",
        "ok",
        "RU sync evidence remains attached to the review bundle"
      )
    )
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

  defp maybe_put_declared_replacement_artifacts(payload, phase, %Change{} = change) do
    refs = replacement_artifacts_for_phase(phase, change)

    if refs == [] do
      payload
    else
      Map.update(payload, :artifacts, refs, fn artifacts -> Enum.uniq(artifacts ++ refs) end)
    end
  end

  defp replacement_artifacts_for_phase(phase, %Change{} = change) do
    refs = replacement_declared_evidence_refs(change)

    lane_refs =
      [refs.attach, refs.registration, refs.pdu_session, refs.ping]
      |> Enum.reject(&is_nil/1)

    rollback_refs =
      [refs.rollback]
      |> Enum.reject(&is_nil/1)

    cond do
      change.scope == "ue_session" and phase in [:verify, :observe, :capture_artifacts] ->
        lane_refs

      change.scope == "replacement_cutover" and phase in [:observe, :capture_artifacts, :rollback] ->
        lane_refs ++ rollback_refs

      true ->
        []
    end
  end

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

  defp replacement_virtual_plan_for_rollback(%Change{} = change) do
    replacement_virtual_plan(change)
    |> Map.put("target_backend", replacement_restore_source(change) || "replacement_shadow")
    |> Map.put(
      "rollback_target",
      replacement_review_rollback_target(change) || replacement_rollback_target(change)
    )
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

  defp replacement_restore_source(%Change{requested_current_backend: current_backend})
       when is_binary(current_backend) and current_backend != "",
       do: current_backend

  defp replacement_restore_source(%Change{current_backend: current_backend})
       when is_binary(current_backend) and current_backend != "",
       do: current_backend

  defp replacement_restore_source(%Change{current_backend: current_backend})
       when is_atom(current_backend) and not is_nil(current_backend),
       do: Atom.to_string(current_backend)

  defp replacement_restore_source(%Change{requested_target_backend: target_backend})
       when is_binary(target_backend) and target_backend != "",
       do: target_backend

  defp replacement_restore_source(%Change{target_backend: target_backend})
       when is_binary(target_backend) and target_backend != "",
       do: target_backend

  defp replacement_restore_source(%Change{target_backend: target_backend})
       when is_atom(target_backend) and not is_nil(target_backend),
       do: Atom.to_string(target_backend)

  defp replacement_restore_source(_change), do: nil

  defp rollback_summary(target_role, restored_from, rollback_target) do
    target = rollback_target || "rollback"

    if is_binary(restored_from) and restored_from != "" and restored_from != target do
      "Rollback returned the #{target_role} lane from #{restored_from} to the declared #{target} target after replacement review failed, keeping the F1-C/E1AP release and re-establishment trail explicit."
    else
      "Rollback returned the #{target_role} lane to the declared #{target} target after replacement review failed, keeping the F1-C/E1AP release and re-establishment trail explicit."
    end
  end

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

  defp simulation_precheck(%Change{metadata: metadata}) do
    if OaiSimulation.simulation_requested?(metadata) do
      OaiSimulation.precheck(metadata)
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

  defp maybe_verify_oai_simulation(%Change{change_id: change_id, metadata: metadata}) do
    if OaiSimulation.simulation_requested?(metadata) do
      OaiSimulation.verify(change_id, metadata)
    else
      {:ok, nil}
    end
  end

  defp maybe_capture_oai_simulation(%Change{change_id: change_id, metadata: metadata}) do
    if OaiSimulation.simulation_requested?(metadata) do
      OaiSimulation.capture_artifacts(change_id, metadata)
    else
      {:ok, nil}
    end
  end

  defp runtime_checks({:ok, %{checks: checks}}) when is_list(checks), do: checks
  defp runtime_checks({:error, _payload}), do: [check("oai_runtime_resolved", false)]
  defp runtime_checks(_), do: []

  defp simulation_checks({:ok, %{checks: checks}}) when is_list(checks), do: checks
  defp simulation_checks({:error, _payload}), do: [check("oai_simulation_resolved", false)]
  defp simulation_checks(_), do: []

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

  defp simulation_payload({:ok, nil}), do: nil
  defp simulation_payload({:ok, payload}), do: payload
  defp simulation_payload({:error, payload}), do: payload
  defp simulation_payload(_), do: nil

  defp put_oai_simulation_result(payload, simulation_result, %Change{} = change) do
    case simulation_payload(simulation_result) do
      nil ->
        payload

      simulation ->
        lane = simulation[:lane] || simulation["lane"]
        statuses = simulation_statuses(simulation)

        payload
        |> put_optional(:simulation_lane, lane)
        |> maybe_put_nested_simulation_status(statuses, change)
    end
  end

  defp maybe_put_nested_simulation_status(payload, statuses, %Change{} = change) do
    if replacement_scope?(change.scope) do
      put_optional(payload, :simulation_status, statuses)
    else
      Enum.reduce(statuses, payload, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)
    end
  end

  defp simulation_statuses(simulation) do
    [:attach_status, :registration_status, :session_status, :ping_status]
    |> Enum.reduce(%{}, fn key, acc ->
      case simulation[key] || simulation[Atom.to_string(key)] do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp maybe_put_oai_simulation_semantics(payload, phase, %Change{} = change) do
    if OaiSimulation.simulation_requested?(change.metadata) do
      payload
      |> maybe_put_oai_simulation_verify_summary(phase)
      |> maybe_put_oai_simulation_capture_review(phase, change)
      |> merge_artifacts(simulation_artifact_refs(payload))
    else
      payload
    end
  end

  defp maybe_put_oai_simulation_verify_summary(payload, :verify) do
    case payload[:summary] || payload["summary"] do
      summary when is_binary(summary) and summary != "" ->
        payload

      _ ->
        Map.put(payload, :summary, simulation_verify_summary(payload))
    end
  end

  defp maybe_put_oai_simulation_verify_summary(payload, _phase), do: payload

  defp maybe_put_oai_simulation_capture_review(payload, :capture_artifacts, %Change{} = change) do
    ref = change.incident_id || change.change_id || "capture"
    review_paths = simulation_review_paths(ref)
    compare_report = simulation_compare_report(payload, change)

    Store.write_json(review_paths.request_snapshot, simulation_request_snapshot(change, payload))
    Store.write_json(review_paths.compare_report, compare_report)

    Store.write_json(
      review_paths.rollback_evidence,
      simulation_rollback_evidence(payload, change, review_paths.compare_report)
    )

    payload
    |> put_in([:bundle, :review], review_paths)
    |> Map.put(:summary, simulation_capture_summary(payload))
    |> Map.put(:failure_class, simulation_failure_class(payload))
    |> Map.put(:comparison_scope, simulation_comparison_scope(payload))
    |> Map.put(:rollback_available, true)
    |> Map.put(:suggested_next, simulation_suggested_next(payload))
    |> Map.put(:checks, simulation_review_checks())
    |> Map.put(
      :rollback_status,
      review_status(
        "ok",
        review_paths.rollback_evidence,
        "repo-local rollback remains reviewable for the simulation lane; no live-lab target was changed"
      )
    )
    |> merge_artifacts(Map.values(review_paths))
  end

  defp maybe_put_oai_simulation_capture_review(payload, _phase, _change), do: payload

  defp simulation_artifact_refs(payload) do
    payload
    |> simulation_status_payload()
    |> Enum.map(fn {_key, value} -> value[:evidence_ref] || value["evidence_ref"] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp simulation_status_payload(payload) do
    payload[:simulation_status] || payload["simulation_status"] ||
      [:attach_status, :registration_status, :session_status, :ping_status]
      |> Enum.reduce(%{}, fn key, acc ->
        case payload[key] || payload[Atom.to_string(key)] do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)
  end

  defp simulation_status_value(payload, key) do
    status_payload = simulation_status_payload(payload)
    value = status_payload[key] || status_payload[Atom.to_string(key)] || %{}
    value[:status] || value["status"]
  end

  defp simulation_status_ok?(payload, key) do
    simulation_status_value(payload, key) in ["ok", "established"]
  end

  defp simulation_failure_class(payload) do
    cond do
      not simulation_status_ok?(payload, :attach_status) -> "attach_failure"
      not simulation_status_ok?(payload, :registration_status) -> "registration_failure"
      not simulation_status_ok?(payload, :session_status) -> "session_failure"
      not simulation_status_ok?(payload, :ping_status) -> "ping_failure"
      true -> nil
    end
  end

  defp simulation_comparison_scope(payload) do
    case simulation_failure_class(payload) do
      "attach_failure" -> "attach"
      "registration_failure" -> "registration"
      "session_failure" -> "session"
      "ping_failure" -> "ping"
      nil -> "ping"
    end
  end

  defp simulation_verify_summary(payload) do
    case simulation_failure_class(payload) do
      nil ->
        "Verify surfaced repo-local simulation proof for attach, registration, session, and ping. These refs are rehearsal evidence only and do not claim live-lab proof."

      failure_class ->
        "Verify surfaced repo-local simulation evidence, but #{String.replace_suffix(failure_class, "_failure", "")} proof is incomplete. Treat this as simulation-only evidence, not live-lab proof."
    end
  end

  defp simulation_capture_summary(payload) do
    case simulation_failure_class(payload) do
      nil ->
        "Capture preserved the repo-local simulation evidence bundle and review notes for attach, registration, session, and ping. This remains simulation proof only, not live-lab proof."

      failure_class ->
        "Capture preserved the repo-local simulation evidence bundle after #{String.replace_suffix(failure_class, "_failure", "")} review diverged. The rollback story remains explicit for the simulation lane and does not imply live-lab proof."
    end
  end

  defp simulation_suggested_next(payload) do
    case simulation_failure_class(payload) do
      nil ->
        [
          "review the simulation compare report before another repo-local mutation",
          "keep the paired rollback request explicit for the next RFsim rehearsal",
          "do not promote simulation proof to live-lab evidence without a real-core run"
        ]

      _ ->
        [
          "inspect the simulation compare report before rerunning the RFsim rehearsal",
          "replay the paired repo-local rollback before the next runtime mutation",
          "treat the captured mismatch as simulation-only until live-lab evidence exists"
        ]
    end
  end

  defp simulation_review_checks do
    [
      review_check("compare_report_ready", "ok", "the simulation compare report is preserved"),
      review_check(
        "simulation_evidence_fetchable",
        "ok",
        "simulation attach/session/ping refs remain readable from repo-visible paths"
      ),
      review_check(
        "rollback_story_explicit",
        "ok",
        "the capture bundle keeps repo-local rollback separate from any live-lab rollback claim"
      )
    ]
  end

  defp simulation_review_paths(ref) do
    %{
      request_snapshot: Store.capture_request_snapshot_path(ref),
      compare_report: Store.capture_compare_report_path(ref),
      rollback_evidence: Store.capture_rollback_evidence_path(ref)
    }
  end

  defp simulation_request_snapshot(%Change{} = change, payload) do
    %{
      captured_at: now_iso8601(),
      scope: change.scope,
      change_id: change.change_id,
      incident_id: change.incident_id,
      reason: change.reason,
      verify_window: change.verify_window,
      target_backend: maybe_to_string(change.target_backend),
      metadata: %{
        oai_runtime: change.metadata[:oai_runtime] || change.metadata["oai_runtime"],
        oai_simulation: change.metadata[:oai_simulation] || change.metadata["oai_simulation"]
      },
      simulation_lane: payload[:simulation_lane] || payload["simulation_lane"],
      simulation_evidence_refs: simulation_artifact_refs(payload)
    }
  end

  defp simulation_compare_report(payload, %Change{} = change) do
    lane = payload[:simulation_lane] || payload["simulation_lane"] || %{}

    %{
      report_id: "sim-cmp-#{change.change_id || "capture"}",
      change_id: change.change_id,
      incident_id: change.incident_id || "#{change.change_id}-capture",
      lane_id: lane[:lane_id] || lane["lane_id"],
      claim_scope: lane[:claim_scope] || lane["claim_scope"],
      evidence_tier: lane[:evidence_tier] || lane["evidence_tier"],
      live_lab_claim: lane[:live_lab_claim] || lane["live_lab_claim"] || false,
      comparison_scope: simulation_comparison_scope(payload),
      failure_class: simulation_failure_class(payload),
      expected_state: %{
        attach: "repo-local attach evidence stays reviewer-visible from the checkout",
        registration: "repo-local registration evidence stays reviewer-visible from the checkout",
        session: "repo-local session evidence stays reviewer-visible from the checkout",
        ping: "repo-local ping evidence stays reviewer-visible from the checkout"
      },
      observed_state: %{
        attach: simulation_status_value(payload, :attach_status),
        registration: simulation_status_value(payload, :registration_status),
        session: simulation_status_value(payload, :session_status),
        ping: simulation_status_value(payload, :ping_status)
      },
      diff_summary:
        case simulation_failure_class(payload) do
          nil ->
            [
              "Attach, registration, session, and ping refs are all reviewable from repo-visible simulation paths.",
              "The capture stays explicitly bounded to repo-local RFsim evidence and does not imply live-lab proof."
            ]

          failure_class ->
            [
              "The #{String.replace_suffix(failure_class, "_failure", "")} step is the first simulation proof gap in the rehearsal lane.",
              "The capture remains explicitly simulation-only so reviewers do not confuse it with live-lab evidence."
            ]
        end,
      evidence_refs: simulation_artifact_refs(payload),
      operator_next_step: List.first(simulation_suggested_next(payload)),
      summary: simulation_capture_summary(payload)
    }
  end

  defp simulation_rollback_evidence(payload, %Change{} = change, compare_report_path) do
    lane = payload[:simulation_lane] || payload["simulation_lane"] || %{}

    %{
      rollback_id: "sim-rbk-#{change.change_id || "capture"}",
      change_id: change.change_id,
      incident_id: change.incident_id || "#{change.change_id}-capture",
      lane_id: lane[:lane_id] || lane["lane_id"],
      claim_scope: lane[:claim_scope] || lane["claim_scope"],
      evidence_tier: lane[:evidence_tier] || lane["evidence_tier"],
      live_lab_claim: lane[:live_lab_claim] || lane["live_lab_claim"] || false,
      rollback_scope: "repo_local_runtime_teardown",
      compare_report_ref: compare_report_path,
      failure_class: simulation_failure_class(payload),
      evidence_refs: Enum.uniq([compare_report_path | simulation_artifact_refs(payload)]),
      operator_notes:
        "Rollback remains a repo-local teardown story for the RFsim rehearsal lane. It does not imply rollback of any live-lab target."
    }
  end

  defp merge_artifacts(payload, refs) do
    refs = Enum.reject(refs, &is_nil/1)

    if refs == [] do
      payload
    else
      Map.update(payload, :artifacts, refs, fn artifacts ->
        Enum.uniq(artifacts ++ refs)
      end)
    end
  end

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

  defp capture_bundle(
         %Change{} = change,
         ref,
         runtime_capture,
         simulation_capture,
         snapshots,
         review
       ) do
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
        configs: runtime_configs(change.change_id),
        simulation: runtime_simulation_bundle(simulation_capture)
      }
    }
    |> put_optional(:review, review)
    |> put_optional(:declared_lane_evidence, replacement_capture_evidence_bundle(change))
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
    compare_report_path = replacement_compare_report_ref(payload, phase, change)

    replacement_paths =
      payload_artifacts(payload) ++ collect_evidence_refs(payload)

    replacement_paths
    |> Enum.filter(&materialized_replacement_path?/1)
    |> Enum.uniq()
    |> Enum.map(fn ref ->
      if File.exists?(ref) and not refresh_replacement_evidence?(ref) do
        ref
      else
        Store.write_json(
          ref,
          replacement_evidence_payload(ref, payload, phase, change, compare_report_path)
        )
      end
    end)
  end

  defp refresh_replacement_evidence?(ref) do
    Path.basename(ref) in ["rollback-evidence.json", "post-rollback-verify.json", "rollback.json"]
  end

  defp replacement_compare_report_ref(payload, phase, %Change{} = change) do
    review = get_in(payload, [:bundle, :review]) || get_in(payload, ["bundle", "review"]) || %{}

    review[:compare_report] || review["compare_report"] ||
      if(phase == :capture_artifacts,
        do:
          Store.capture_compare_report_path(change.incident_id || change.change_id || "capture"),
        else: nil
      )
  end

  defp replacement_evidence_payload(ref, payload, phase, %Change{} = change, compare_report_path) do
    case Path.basename(ref) do
      "rollback-evidence.json" ->
        replacement_rollback_evidence(payload, phase, change, compare_report_path)

      "post-rollback-verify.json" ->
        replacement_post_rollback_verify(payload, change)

      "rollback.json" ->
        if phase == :rollback do
          replacement_post_rollback_verify(payload, change)
        else
          replacement_rollback_evidence(payload, phase, change, compare_report_path)
        end

      _ ->
        replacement_evidence_stub(ref, payload, phase, change)
    end
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
      expected_state: replacement_expected_state(payload, failure_class),
      observed_state: replacement_observed_state(payload, failure_class),
      gate_class: gate_class,
      failure_class: failure_class,
      ngap_subset:
        payload[:ngap_subset] || payload["ngap_subset"] || replacement["ngap_subset"] || %{},
      protocol_claims:
        payload[:protocol_claims] || payload["protocol_claims"] ||
          replacement_protocol_claims(change),
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
    failure_class = payload[:failure_class] || payload["failure_class"]
    ngap_subset = payload[:ngap_subset] || payload["ngap_subset"] || %{}

    rollback_target =
      payload[:rollback_target] || payload["rollback_target"] ||
        replacement_rollback_target(change)

    restored_from =
      payload[:restored_from] || payload["restored_from"] || replacement_restore_source(change)

    post_rollback_verify_ref =
      if phase == :rollback,
        do: replacement_evidence_ref(:rollback, change, "post-rollback-verify"),
        else: nil

    %{
      rollback_id: "rbk-#{change.change_id || phase}",
      change_id: change.change_id,
      incident_id: change.incident_id || "#{change.change_id}-capture",
      target_profile: payload[:target_profile] || payload["target_profile"],
      rollback_target: rollback_target,
      rollback_reason: replacement_rollback_reason(phase, gate_class),
      triggering_gate: gate_class,
      failure_class: failure_class,
      ngap_subset: ngap_subset,
      protocol_claims:
        payload[:protocol_claims] || payload["protocol_claims"] ||
          replacement_protocol_claims(change),
      pre_rollback_state: %{
        compare_report_ref: compare_report_path,
        gate_class: gate_class,
        cutover_state: payload[:target_backend] || payload["target_backend"],
        observed_problem: payload[:summary] || payload["summary"]
      },
      post_rollback_state: %{
        rollback_target: rollback_target,
        restored_from: restored_from,
        cutover_state: if(phase == :rollback, do: "rolled_back", else: "not_executed"),
        repair_state:
          if(phase == :rollback,
            do: "rollback target restored and ready for another bounded run",
            else: "rollback remains available and explicit for the next mutation"
          ),
        post_rollback_verify_ref: post_rollback_verify_ref
      },
      recovery_check: %{
        status: replacement_recovery_status(phase, gate_class),
        checks: replacement_recovery_checks(phase, gate_class)
      },
      evidence_refs:
        ([compare_report_path, post_rollback_verify_ref] ++
           replacement_report_evidence_refs(payload, change, phase))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      operator_notes:
        if(phase == :rollback,
          do:
            "Rollback preserved a reviewable recovery path and kept the F1-C/E1AP release, re-establishment, and bounded handover-adjacent refresh trail explicit.",
          else:
            "Rollback was not executed, but the captured evidence preserves the explicit F1-C/E1AP recovery trail, including the bounded handover-adjacent refresh state."
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

  defp replacement_post_rollback_verify(payload, %Change{} = change) do
    rollback_target =
      payload[:rollback_target] || payload["rollback_target"] ||
        replacement_review_rollback_target(change)

    restored_from =
      payload[:restored_from] || payload["restored_from"] || replacement_restore_source(change)

    interface_status = payload[:interface_status] || payload["interface_status"] || %{}
    release_status = payload[:release_status] || payload["release_status"]
    core_link_status = payload[:core_link_status] || payload["core_link_status"]
    ru_status = payload[:ru_status] || payload["ru_status"]

    %{
      captured_at: now_iso8601(),
      command: "verify",
      phase: "post_rollback",
      change_id: change.change_id,
      incident_id: change.incident_id,
      target_profile: payload[:target_profile] || payload["target_profile"],
      rollback_target: rollback_target,
      restored_from: restored_from,
      verification_checks: replacement_recovery_checks(:rollback, "pass"),
      restored_state: %{
        summary:
          "Post-rollback verification confirms the declared #{rollback_target} target and the F1-C/E1AP release and re-establishment trail are reviewable without SSH archaeology.",
        release_status: status_label(release_status),
        core_link_status: status_label(core_link_status),
        ru_status: status_label(ru_status)
      },
      protocol_claims:
        payload[:protocol_claims] || payload["protocol_claims"] ||
          replacement_protocol_claims(change),
      evidence_refs:
        ([release_status, core_link_status, ru_status] ++ Map.values(interface_status))
        |> Enum.map(fn
          %{evidence_ref: evidence_ref} -> evidence_ref
          %{"evidence_ref" => evidence_ref} -> evidence_ref
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp replacement_expected_state(_payload, "ru_failure") do
    %{
      host_preflight: "ok",
      ru_sync: "ok",
      timing_source: "stable",
      fronthaul: "ok"
    }
  end

  defp replacement_expected_state(payload, _failure_class) do
    %{
      attach: status_label(payload[:attach_status] || payload["attach_status"]),
      pdu_session: status_label(payload[:pdu_session_status] || payload["pdu_session_status"]),
      ping: status_label(payload[:ping_status] || payload["ping_status"]),
      release: status_label(payload[:release_status] || payload["release_status"])
    }
  end

  defp replacement_observed_state(payload, "ru_failure") do
    plane_status = payload[:plane_status] || payload["plane_status"] || %{}
    interface_status = payload[:interface_status] || payload["interface_status"] || %{}

    %{
      host_preflight:
        status_label(Map.get(plane_status, :m_plane) || Map.get(plane_status, "m_plane")),
      ru_sync: status_label(payload[:ru_status] || payload["ru_status"]),
      timing_source:
        status_label(Map.get(plane_status, :s_plane) || Map.get(plane_status, "s_plane")),
      fronthaul:
        status_label(
          Map.get(interface_status, "ru_fronthaul") || Map.get(interface_status, :ru_fronthaul)
        )
    }
  end

  defp replacement_observed_state(payload, _failure_class),
    do: replacement_expected_state(payload, nil)

  defp status_label(%{status: status}) when is_binary(status), do: status
  defp status_label(%{"status" => status}) when is_binary(status), do: status
  defp status_label(_value), do: "unknown"

  defp replacement_comparison_scope(_phase, "ru_failure"), do: "ru_sync"
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

  defp replacement_diff_summary(_gate_class, "ru_failure") do
    [
      "RU sync never reached a deterministic ready state for the declared lane.",
      "The replay bundle keeps host readiness, timing, and fronthaul evidence explicit before another attach attempt."
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

  defp replacement_diff_summary(_gate_class, "cutover_or_rollback_failure") do
    [
      "The captured mismatch keeps F1-C UE-context release and re-establishment guardrails explicit on the declared lane.",
      "The review bundle also keeps E1AP bearer release, re-establishment, and bounded handover-adjacent refresh explicit without implying full mobility support.",
      "The rollback target remains explicit for replay and recovery."
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
      |> collect_evidence_refs()
      |> Kernel.++(payload_artifacts(payload))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(16)

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
      "The captured mismatch made the declared rollback target safer than leaving the F1-C/E1AP release and re-establishment drift active."

  defp replacement_rollback_reason(_phase, "pass"),
    do:
      "Rollback was not required because the declared lane stayed within the live-lab proof envelope."

  defp replacement_rollback_reason(_phase, _gate_class),
    do:
      "The captured mismatch keeps rollback explicit until the F1-C/E1AP release and re-establishment trail is corrected."

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

  defp runtime_simulation_bundle(nil), do: nil

  defp runtime_simulation_bundle(simulation_capture) when is_map(simulation_capture) do
    lane = simulation_capture[:lane] || simulation_capture["lane"] || %{}

    %{
      lane_id: lane[:lane_id] || lane["lane_id"],
      claim_scope: lane[:claim_scope] || lane["claim_scope"],
      evidence_tier: lane[:evidence_tier] || lane["evidence_tier"],
      live_lab_claim: lane[:live_lab_claim] || lane["live_lab_claim"] || false,
      ue_conf_path: lane[:ue_conf_path] || lane["ue_conf_path"],
      attach:
        get_in(simulation_capture, [:attach_status, :evidence_ref]) ||
          get_in(simulation_capture, ["attach_status", "evidence_ref"]),
      registration:
        get_in(simulation_capture, [:registration_status, :evidence_ref]) ||
          get_in(simulation_capture, ["registration_status", "evidence_ref"]),
      session:
        get_in(simulation_capture, [:session_status, :evidence_ref]) ||
          get_in(simulation_capture, ["session_status", "evidence_ref"]),
      ping:
        get_in(simulation_capture, [:ping_status, :evidence_ref]) ||
          get_in(simulation_capture, ["ping_status", "evidence_ref"])
    }
  end

  defp replacement_capture_evidence_bundle(%Change{} = change) do
    refs = replacement_declared_evidence_refs(change)

    evidence = %{
      target_profile: replacement_metadata(change)["target_profile"],
      attach_ref: refs.attach,
      registration_ref: refs.registration,
      pdu_session_ref: refs.pdu_session,
      ping_ref: refs.ping,
      rollback_ref: refs.rollback
    }

    if Enum.any?(Map.delete(evidence, :target_profile), fn {_key, value} ->
         is_binary(value) and value != ""
       end) do
      evidence
    else
      nil
    end
  end

  defp recent_change_refs(limit) do
    [
      "prechecks",
      "plans",
      "changes",
      "observations",
      "verify",
      "captures",
      "approvals",
      "rollback_plans"
    ]
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
      Store.observation_path(change_id),
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
