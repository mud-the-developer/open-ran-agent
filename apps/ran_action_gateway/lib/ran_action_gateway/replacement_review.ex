defmodule RanActionGateway.ReplacementReview do
  @moduledoc false

  alias RanActionGateway.Change
  alias RanActionGateway.Store

  @replacement_scopes ~w(gnb target_host ue_session ru_link core_link replacement_cutover)

  def enrich(payload, _phase, %Change{scope: scope}, _checks) when scope in @replacement_scopes,
    do: payload

  def enrich(payload, _phase, _change, _checks), do: payload

  def capture_review(%Change{scope: scope}, ref) when scope in @replacement_scopes do
    %{
      request_snapshot: Store.capture_request_snapshot_path(ref),
      compare_report: Store.capture_compare_report_path(ref),
      rollback_evidence: Store.capture_rollback_evidence_path(ref)
    }
  end

  def capture_review(_change, _ref), do: nil
end
