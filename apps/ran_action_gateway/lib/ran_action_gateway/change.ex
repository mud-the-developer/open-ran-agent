defmodule RanActionGateway.Change do
  @moduledoc """
  Bootstrap action contract shared by `ranctl` and BEAM-side change workflows.
  """

  defstruct [
    :scope,
    :target_ref,
    :cell_group,
    :target_backend,
    :current_backend,
    :rollback_target,
    :change_id,
    :incident_id,
    :reason,
    :idempotency_key,
    approval: %{},
    dry_run: false,
    ttl: "15m",
    verify_window: %{duration: "30s", checks: []},
    max_blast_radius: "single_cell_group",
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          scope: String.t(),
          target_ref: String.t() | nil,
          cell_group: String.t() | nil,
          target_backend: atom() | String.t() | nil,
          current_backend: atom() | String.t() | nil,
          rollback_target: String.t() | nil,
          change_id: String.t(),
          incident_id: String.t() | nil,
          reason: String.t(),
          idempotency_key: String.t(),
          approval: map(),
          dry_run: boolean(),
          ttl: String.t(),
          verify_window: map(),
          max_blast_radius: String.t(),
          metadata: map()
        }
end
