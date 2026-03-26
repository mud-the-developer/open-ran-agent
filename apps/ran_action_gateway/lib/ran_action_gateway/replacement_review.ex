defmodule RanActionGateway.ReplacementReview do
  @moduledoc false

  alias RanActionGateway.Change
  alias RanActionGateway.Store

  @baseline_profile "oai_visible_5g_standards_baseline_v1"
  @baseline_ref "subprojects/ran_replacement/notes/16-oai-visible-5g-standards-conformance-baseline.md"
  @replacement_scopes ~w(gnb target_host ue_session ru_link core_link replacement_cutover)

  def enrich(payload, phase, %Change{scope: scope} = change, _checks)
      when scope in @replacement_scopes do
    replacement = replacement_metadata(change)

    payload
    |> put_value(:target_ref, change.target_ref)
    |> put_value(:target_profile, replacement["target_profile"])
    |> put_value(:target_backend, replacement_target_backend(payload, change))
    |> put_value(:rollback_target, replacement_rollback_target(payload, change))
    |> put_value(:rollback_available, not is_nil(replacement_rollback_target(payload, change)))
    |> put_value(:core_profile, replacement["core_profile"])
    |> put_value(:conformance_claim, conformance_claim(phase))
    |> put_value(:core_endpoint, core_endpoint(replacement))
    |> put_value(:ngap_subset, replacement["ngap_subset"])
    |> maybe_put_target_host_semantics(phase, change)
    |> put_value(:failure_class, replacement_failure_class(payload, phase, change))
    |> maybe_put_artifacts(phase, change)
  end

  def enrich(payload, _phase, _change, _checks), do: payload

  def capture_review(%Change{scope: scope}, ref) when scope in @replacement_scopes do
    %{
      request_snapshot: Store.capture_request_snapshot_path(ref),
      compare_report: Store.capture_compare_report_path(ref),
      rollback_evidence: Store.capture_rollback_evidence_path(ref)
    }
  end

  def capture_review(_change, _ref), do: nil

  defp replacement_metadata(%Change{metadata: metadata}) do
    metadata[:replacement] || metadata["replacement"] || %{}
  end

  defp replacement_target_backend(payload, %Change{scope: "target_host"} = change) do
    if current_value(payload, :command) == "precheck" do
      "replacement_shadow"
    else
      replacement_target_backend(payload, %{change | scope: "gnb"})
    end
  end

  defp replacement_target_backend(payload, %Change{} = change) do
    normalized_value(current_value(payload, :target_backend)) ||
      change.requested_target_backend ||
      (change.target_backend && Atom.to_string(change.target_backend)) ||
      "replacement_shadow"
  end

  defp replacement_rollback_target(payload, %Change{} = change) do
    normalized_value(current_value(payload, :rollback_target)) ||
      change.rollback_target ||
      "oai_reference"
  end

  defp conformance_claim(_phase) do
    %{
      profile: @baseline_profile,
      evidence_tier: "milestone_proof",
      baseline_ref: @baseline_ref
    }
  end

  defp core_endpoint(replacement) do
    case replacement["open5gs_core"] do
      nil ->
        nil

      core ->
        %{
          profile: core["profile"] || replacement["core_profile"],
          release_ref: core["release_ref"],
          n2: core["n2"],
          n3: core["n3"]
        }
    end
  end

  defp maybe_put_target_host_semantics(payload, :precheck, %Change{scope: "target_host"} = change) do
    replacement = replacement_metadata(change)
    core = replacement["open5gs_core"] || %{}
    blocked? = current_value(payload, :status) in ["failed", "blocked"]

    Map.put(payload, :plane_status, %{
      s_plane: %{
        status: if(blocked?, do: "blocked", else: "ok"),
        evidence_ref: replacement_artifact(:precheck, change, "ptp-state"),
        reason:
          if(blocked?, do: "timing and fronthaul resources are not yet fully proven", else: nil)
      },
      m_plane: %{
        status: "ok",
        evidence_ref: replacement_artifact(:precheck, change, "host-inventory"),
        reason: nil
      },
      c_plane: %{
        status: if(blocked?, do: "blocked", else: "ok"),
        evidence_ref: replacement_artifact(:precheck, change, "core-link"),
        reason: if(blocked?, do: "cutover to the replacement lane is not yet allowed", else: nil)
      },
      u_plane: %{
        status: if(blocked?, do: "blocked", else: "ok"),
        evidence_ref: replacement_artifact(:precheck, change, "user-plane"),
        reason: if(blocked?, do: "user-plane path is not yet declared ready", else: nil)
      }
    })
    |> put_value(:ru_status, %{
      status: if(blocked?, do: "blocked", else: "ok"),
      evidence_ref: replacement_artifact(:precheck, change, "ru-sync"),
      reason:
        if(blocked?, do: "RU sync has not been demonstrated for the declared profile", else: nil)
    })
    |> put_value(:checks, [
      %{
        "name" => "host_preflight",
        "status" => if(blocked?, do: "blocked", else: "ok")
      },
      %{
        "name" => "ru_sync",
        "status" => if(blocked?, do: "blocked", else: "ok")
      },
      %{
        "name" => "core_link_reachable",
        "status" => if(core["profile"], do: "ok", else: "blocked")
      }
    ])
  end

  defp maybe_put_target_host_semantics(payload, _phase, _change), do: payload

  defp replacement_failure_class(payload, :precheck, %Change{scope: "target_host"}) do
    current_value(payload, :failure_class) || "ru_failure"
  end

  defp replacement_failure_class(payload, _phase, _change),
    do: current_value(payload, :failure_class)

  defp maybe_put_artifacts(payload, phase, %Change{} = change) do
    artifacts =
      payload
      |> existing_artifacts()
      |> Kernel.++(phase_artifacts(phase, change))
      |> Kernel.++(collect_evidence_refs(payload))
      |> Enum.reject(&blank?/1)
      |> Enum.uniq()

    put_value(payload, :artifacts, artifacts)
  end

  defp existing_artifacts(payload) do
    case current_value(payload, :artifacts) do
      artifacts when is_list(artifacts) -> artifacts
      _ -> []
    end
  end

  defp phase_artifacts(:plan, %Change{} = change) do
    [
      Store.plan_path(change.change_id),
      Store.rollback_plan_path(change.change_id)
    ]
  end

  defp phase_artifacts(:apply, %Change{} = change) do
    [
      Store.change_state_path(change.change_id),
      Store.rollback_plan_path(change.change_id)
    ]
  end

  defp phase_artifacts(:precheck, %Change{} = change) do
    [
      replacement_artifact(:precheck, change, safe_suffix(change.target_ref || change.change_id)),
      replacement_artifact(:precheck, change, "ru-sync"),
      replacement_artifact(:precheck, change, "core-link")
    ]
  end

  defp phase_artifacts(:verify, %Change{} = change) do
    [
      Store.verify_path(change.change_id),
      replacement_artifact(:verify, change, "attach"),
      replacement_artifact(:verify, change, "registration"),
      replacement_artifact(:verify, change, "pdu-session"),
      replacement_artifact(:verify, change, "ping")
    ]
  end

  defp phase_artifacts(:observe, %Change{} = change) do
    [
      replacement_artifact(:observe, change, "attach"),
      replacement_artifact(:observe, change, "registration"),
      replacement_artifact(:observe, change, "pdu-session"),
      replacement_artifact(:observe, change, "ping"),
      replacement_artifact(:observe, change, "rollback-evidence")
    ]
  end

  defp phase_artifacts(:capture_artifacts, %Change{} = change) do
    ref = change.incident_id || change.change_id

    [
      Store.capture_path(ref),
      Store.capture_compare_report_path(ref),
      Store.capture_request_snapshot_path(ref),
      Store.capture_rollback_evidence_path(ref),
      replacement_artifact(:capture_artifacts, change, "attach"),
      replacement_artifact(:capture_artifacts, change, "registration"),
      replacement_artifact(:capture_artifacts, change, "pdu-session"),
      replacement_artifact(:capture_artifacts, change, "ping")
    ]
  end

  defp phase_artifacts(:rollback, %Change{} = change) do
    [
      Store.rollback_plan_path(change.change_id),
      replacement_artifact(:rollback, change, "rollback-evidence"),
      replacement_artifact(:rollback, change, "post-rollback-verify")
    ]
  end

  defp phase_artifacts(_phase, _change), do: []

  defp collect_evidence_refs(%{} = map) do
    Enum.flat_map(map, fn
      {:evidence_ref, value} when is_binary(value) -> [value]
      {"evidence_ref", value} when is_binary(value) -> [value]
      {_key, value} when is_map(value) -> collect_evidence_refs(value)
      {_key, value} when is_list(value) -> Enum.flat_map(value, &collect_evidence_refs/1)
      _ -> []
    end)
  end

  defp collect_evidence_refs(_value), do: []

  defp replacement_artifact(:capture_artifacts, %Change{} = change, suffix) do
    Path.join(["artifacts", "replacement", "capture", change.change_id, "#{suffix}.json"])
  end

  defp replacement_artifact(phase, %Change{} = change, suffix) do
    Path.join([
      "artifacts",
      "replacement",
      Atom.to_string(phase),
      change.change_id,
      "#{suffix}.json"
    ])
  end

  defp current_value(payload, key) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  defp put_value(payload, _key, nil), do: payload

  defp put_value(payload, key, value) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(payload, key) -> Map.put(payload, key, value)
      Map.has_key?(payload, string_key) -> Map.put(payload, string_key, value)
      true -> Map.put(payload, key, value)
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp normalized_value("nil"), do: nil
  defp normalized_value(value), do: value

  defp safe_suffix(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "-")
  end
end
