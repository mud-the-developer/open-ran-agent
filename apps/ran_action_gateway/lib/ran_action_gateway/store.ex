defmodule RanActionGateway.Store do
  @moduledoc """
  File-backed storage for bootstrap plans, change state, and artifact bundles.
  """

  @artifact_root "artifacts"
  @json_artifact_kinds ~w(
    prechecks
    plans
    changes
    verify
    captures
    approvals
    rollback_plans
    config_snapshots
    control_snapshots
    probe_snapshots
  )
  @directory_artifact_kinds ~w(runtime releases control_state)

  @spec artifact_root() :: String.t()
  def artifact_root, do: @artifact_root

  @spec json_artifact_kinds() :: [String.t()]
  def json_artifact_kinds, do: @json_artifact_kinds

  @spec directory_artifact_kinds() :: [String.t()]
  def directory_artifact_kinds, do: @directory_artifact_kinds

  @spec ensure_root!() :: String.t()
  def ensure_root! do
    File.mkdir_p!(@artifact_root)
    @artifact_root
  end

  @spec plan_path(String.t()) :: String.t()
  def plan_path(change_id), do: Path.join([@artifact_root, "plans", "#{change_id}.json"])

  @spec precheck_path(String.t()) :: String.t()
  def precheck_path(change_id), do: Path.join([@artifact_root, "prechecks", "#{change_id}.json"])

  @spec change_state_path(String.t()) :: String.t()
  def change_state_path(change_id),
    do: Path.join([@artifact_root, "changes", "#{change_id}.json"])

  @spec verify_path(String.t()) :: String.t()
  def verify_path(change_id), do: Path.join([@artifact_root, "verify", "#{change_id}.json"])

  @spec capture_path(String.t()) :: String.t()
  def capture_path(ref), do: Path.join([@artifact_root, "captures", "#{ref}.json"])

  @spec capture_compare_report_path(String.t()) :: String.t()
  def capture_compare_report_path(ref),
    do: Path.join([@artifact_root, "captures", "#{ref}-compare-report.json"])

  @spec capture_request_snapshot_path(String.t()) :: String.t()
  def capture_request_snapshot_path(ref),
    do: Path.join([@artifact_root, "captures", "#{ref}-request.json"])

  @spec capture_rollback_evidence_path(String.t()) :: String.t()
  def capture_rollback_evidence_path(ref),
    do: Path.join([@artifact_root, "captures", "#{ref}-rollback-evidence.json"])

  @spec approval_path(String.t(), String.t()) :: String.t()
  def approval_path(change_id, command \\ "apply") do
    Path.join([@artifact_root, "approvals", "#{change_id}-#{command}.json"])
  end

  @spec rollback_plan_path(String.t()) :: String.t()
  def rollback_plan_path(change_id),
    do: Path.join([@artifact_root, "rollback_plans", "#{change_id}.json"])

  @spec config_snapshot_path(String.t()) :: String.t()
  def config_snapshot_path(ref),
    do: Path.join([@artifact_root, "config_snapshots", "#{ref}.json"])

  @spec control_snapshot_path(String.t()) :: String.t()
  def control_snapshot_path(ref),
    do: Path.join([@artifact_root, "control_snapshots", "#{ref}.json"])

  @spec probe_snapshot_path(String.t()) :: String.t()
  def probe_snapshot_path(ref),
    do: Path.join([@artifact_root, "probe_snapshots", "#{ref}.json"])

  @spec control_state_path(String.t()) :: String.t()
  def control_state_path(cell_group_id),
    do: Path.join([@artifact_root, "control_state", "#{cell_group_id}.json"])

  @spec runtime_dir(String.t()) :: String.t()
  def runtime_dir(change_id), do: Path.join([@artifact_root, "runtime", change_id])

  @spec runtime_compose_path(String.t()) :: String.t()
  def runtime_compose_path(change_id),
    do: Path.join([runtime_dir(change_id), "docker-compose.yml"])

  @spec runtime_conf_dir(String.t()) :: String.t()
  def runtime_conf_dir(change_id), do: Path.join([runtime_dir(change_id), "conf"])

  @spec runtime_conf_path(String.t(), String.t()) :: String.t()
  def runtime_conf_path(change_id, role) do
    Path.join([runtime_conf_dir(change_id), "#{role}.conf"])
  end

  @spec runtime_log_path(String.t(), String.t()) :: String.t()
  def runtime_log_path(change_id, service_name) do
    Path.join([runtime_dir(change_id), "logs", "#{service_name}.log"])
  end

  @spec write_json(String.t(), map()) :: String.t()
  def write_json(path, payload) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, JSON.encode!(payload))
    path
  end

  @spec read_json(String.t()) :: {:ok, map()} | {:error, :enoent | term()}
  def read_json(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- JSON.decode(body) do
      {:ok, payload}
    else
      {:error, :enoent} = error -> error
      {:error, reason} -> {:error, reason}
    end
  end
end
