defmodule RanActionGateway.OaiSimulation do
  @moduledoc """
  Repo-local simulation proof surface for OAI split RFsim lanes.

  This module keeps simulation-only UE/core/session evidence separate from the
  live-lab replacement lane. It validates repo-local evidence refs and exposes
  them to `precheck`, `verify`, and `capture-artifacts`.
  """

  @default_simulation %{
    "lane_id" => "oai_split_rfsim_repo_local_v1",
    "claim_scope" => "repo_local_simulation",
    "evidence_tier" => "simulation",
    "live_lab_claim" => false,
    "core_mode" => "simulated"
  }

  @required_fields ~w(
    ue_conf_path
    attach_evidence_path
    registration_evidence_path
    session_evidence_path
    ping_evidence_path
  )

  @spec simulation_requested?(map()) :: boolean()
  def simulation_requested?(metadata) when is_map(metadata) do
    is_map(Map.get(metadata, "oai_simulation")) or is_map(Map.get(metadata, :oai_simulation))
  end

  def simulation_requested?(_metadata), do: false

  @spec precheck(map()) :: {:ok, map()} | {:error, map()}
  def precheck(metadata) do
    with {:ok, spec} <- resolve(metadata) do
      checks =
        [
          check(
            "simulation_claim_scope_repo_local",
            spec["claim_scope"] == "repo_local_simulation"
          ),
          check("simulation_live_lab_claim_disabled", spec["live_lab_claim"] == false),
          check("simulation_ue_conf_present", File.exists?(spec["ue_conf_path"])),
          check(
            "simulation_ue_conf_declares_imsi",
            body_matches?(spec["ue_conf_path"], ~r/imsi\s*=\s*"/)
          ),
          check(
            "simulation_ue_conf_declares_pdu_session",
            body_matches?(spec["ue_conf_path"], ~r/pdu_sessions\s*=\s*\(/)
          )
        ] ++ evidence_checks(spec)

      {:ok,
       %{
         status: status_from_checks(checks),
         lane: public_spec(spec),
         checks: checks,
         evidence_refs: evidence_refs(spec)
       }}
    end
  end

  @spec verify(String.t(), map()) :: {:ok, map()} | {:error, map()}
  def verify(_change_id, metadata) do
    with {:ok, spec} <- resolve(metadata) do
      attach = load_evidence(spec["attach_evidence_path"], "attach")
      registration = load_evidence(spec["registration_evidence_path"], "registration")
      session = load_evidence(spec["session_evidence_path"], "session")
      ping = load_evidence(spec["ping_evidence_path"], "ping")

      checks = [
        check("simulation_attach_proven", evidence_ok?(attach)),
        check("simulation_registration_proven", evidence_ok?(registration)),
        check("simulation_session_proven", evidence_ok?(session)),
        check("simulation_ping_proven", evidence_ok?(ping))
      ]

      {:ok,
       %{
         status: status_from_checks(checks),
         lane: public_spec(spec),
         checks: checks,
         attach_status: attach_status(spec, attach),
         registration_status: registration_status(spec, registration),
         session_status: session_status(spec, session),
         ping_status: ping_status(spec, ping),
         evidence_refs:
           evidence_refs_from_statuses(%{
             attach_status: attach_status(spec, attach),
             registration_status: registration_status(spec, registration),
             session_status: session_status(spec, session),
             ping_status: ping_status(spec, ping)
           })
       }}
    end
  end

  @spec capture_artifacts(String.t(), map()) :: {:ok, map()} | {:error, map()}
  def capture_artifacts(change_id, metadata) do
    with {:ok, verify} <- verify(change_id, metadata) do
      {:ok,
       verify
       |> Map.put(:evidence_refs, evidence_refs_from_statuses(verify))
       |> Map.put(:status, verify[:status] || verify["status"])}
    end
  end

  defp resolve(metadata) do
    spec =
      metadata
      |> Map.get("oai_simulation", Map.get(metadata, :oai_simulation, %{}))
      |> normalize_map_keys()
      |> then(&Map.merge(@default_simulation, &1))

    missing =
      Enum.filter(@required_fields, fn field ->
        spec[field] in [nil, ""]
      end)

    case missing do
      [] ->
        {:ok, spec}

      _ ->
        {:error,
         %{
           status: "invalid_oai_simulation_spec",
           errors:
             Enum.map(
               missing,
               &"#{&1} is required for repo-local OAI simulation proof"
             )
         }}
    end
  end

  defp public_spec(spec) do
    %{
      lane_id: spec["lane_id"],
      claim_scope: spec["claim_scope"],
      evidence_tier: spec["evidence_tier"],
      live_lab_claim: spec["live_lab_claim"],
      core_mode: spec["core_mode"],
      ue_conf_path: spec["ue_conf_path"]
    }
  end

  defp evidence_refs(spec) do
    %{
      attach: spec["attach_evidence_path"],
      registration: spec["registration_evidence_path"],
      session: spec["session_evidence_path"],
      ping: spec["ping_evidence_path"]
    }
  end

  defp evidence_checks(spec) do
    [
      check(
        "simulation_attach_evidence_ready",
        evidence_ok?(load_evidence(spec["attach_evidence_path"], "attach"))
      ),
      check(
        "simulation_registration_evidence_ready",
        evidence_ok?(load_evidence(spec["registration_evidence_path"], "registration"))
      ),
      check(
        "simulation_session_evidence_ready",
        evidence_ok?(load_evidence(spec["session_evidence_path"], "session"))
      ),
      check(
        "simulation_ping_evidence_ready",
        evidence_ok?(load_evidence(spec["ping_evidence_path"], "ping"))
      )
    ]
  end

  defp load_evidence(path, expected_kind) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- JSON.decode(body) do
      payload = normalize_map_keys(payload)

      %{
        "path" => path,
        "kind" => payload["kind"],
        "status" => payload["status"],
        "summary" => payload["summary"],
        "payload" => payload,
        "ok" => payload["kind"] == expected_kind and payload["status"] == "ok"
      }
    else
      _ ->
        %{
          "path" => path,
          "kind" => expected_kind,
          "status" => "failed",
          "summary" => "evidence could not be read or decoded",
          "payload" => %{},
          "ok" => false
        }
    end
  end

  defp load_evidence(_path, expected_kind) do
    %{
      "path" => nil,
      "kind" => expected_kind,
      "status" => "failed",
      "summary" => "evidence path is missing",
      "payload" => %{},
      "ok" => false
    }
  end

  defp evidence_ok?(%{"ok" => ok}), do: ok
  defp evidence_ok?(_evidence), do: false

  defp attach_status(spec, evidence) do
    payload = evidence["payload"] || %{}

    %{
      status: if(evidence_ok?(evidence), do: "ok", else: "failed"),
      evidence_ref: evidence["path"],
      evidence_tier: spec["evidence_tier"],
      summary: evidence["summary"],
      ue_ref: payload["ue"],
      imsi: payload["imsi"]
    }
  end

  defp registration_status(spec, evidence) do
    payload = evidence["payload"] || %{}

    %{
      status: if(evidence_ok?(evidence), do: "ok", else: "failed"),
      evidence_ref: evidence["path"],
      evidence_tier: spec["evidence_tier"],
      summary: evidence["summary"],
      core_mode: spec["core_mode"],
      amf_ref: payload["amf"]
    }
  end

  defp session_status(spec, evidence) do
    payload = evidence["payload"] || %{}

    %{
      status: if(evidence_ok?(evidence), do: "established", else: "failed"),
      evidence_ref: evidence["path"],
      evidence_tier: spec["evidence_tier"],
      summary: evidence["summary"],
      dnn: payload["dnn"],
      pdu_type: payload["pdu_type"],
      ping_target: payload["ping_target"]
    }
  end

  defp ping_status(spec, evidence) do
    payload = evidence["payload"] || %{}

    %{
      status: if(evidence_ok?(evidence), do: "ok", else: "failed"),
      evidence_ref: evidence["path"],
      evidence_tier: spec["evidence_tier"],
      summary: evidence["summary"],
      target: payload["target"],
      packets_tx: payload["packets_tx"],
      packets_rx: payload["packets_rx"]
    }
  end

  defp evidence_refs_from_statuses(verify) do
    %{
      attach: get_in(verify, [:attach_status, :evidence_ref]),
      registration: get_in(verify, [:registration_status, :evidence_ref]),
      session: get_in(verify, [:session_status, :evidence_ref]),
      ping: get_in(verify, [:ping_status, :evidence_ref])
    }
  end

  defp status_from_checks(checks) do
    if Enum.any?(checks, &(&1["status"] == "failed")), do: "failed", else: "ok"
  end

  defp normalize_map_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_map_keys(_), do: %{}

  defp body_matches?(path, regex) do
    case File.read(path) do
      {:ok, body} -> Regex.match?(regex, body)
      _ -> false
    end
  end

  defp check(name, true), do: %{"name" => name, "status" => "passed"}
  defp check(name, false), do: %{"name" => name, "status" => "failed"}
end
