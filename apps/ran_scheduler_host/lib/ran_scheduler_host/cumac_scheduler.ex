defmodule RanSchedulerHost.CumacScheduler do
  @moduledoc """
  Contract-host adapter for future cuMAC-backed scheduling.

  This is still not a real cuMAC runtime, but it now produces executable slot
  plans so DU-high and `ranctl` can validate scheduler selection and replay
  semantics before native integration exists.
  """

  @behaviour RanSchedulerHost.Adapter
  alias RanSchedulerHost.SlotPlan

  @impl true
  def capabilities do
    %{
      adapter: :cumac_scheduler,
      supports_replay: true,
      supports_external_acceleration: true,
      status: :bootstrap,
      support_posture: :bounded_clean_room_runtime,
      promotion_state: :bounded_clean_room_runtime,
      declared_target_profile: "cumac_scheduler_clean_room_runtime_v1",
      rollback_target: :cpu_scheduler,
      failure_domain: :cell_group,
      supported_claims: [
        :executable_slot_plan_runtime,
        :cell_group_scoped_scheduler_ownership,
        :explicit_cpu_rollback_target
      ],
      unsupported_claims: [
        :external_scheduler_worker_proof,
        :runtime_timing_guarantee,
        :attach_validation_claim
      ],
      verify_evidence_refs: [
        "apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs",
        "apps/ran_du_high/test/ran_du_high_test.exs"
      ],
      rollback_evidence_refs: [
        "apps/ran_scheduler_host/test/ran_scheduler_host/cumac_scheduler_test.exs",
        "apps/ran_du_high/test/ran_du_high_test.exs"
      ],
      health_model_ref: "docs/architecture/03-failure-domains.md",
      failure_domain_refs: [
        "docs/architecture/02-otp-apps-and-supervision.md",
        "docs/architecture/03-failure-domains.md"
      ],
      future_expansion_requirements: [
        :external_scheduler_worker_contract,
        :runtime_timing_guarantee,
        :attach_validation_evidence
      ]
    }
  end

  @impl true
  def init_session(opts) do
    {:ok,
     %{
       adapter: :cumac_scheduler,
       pipeline_ref: Keyword.get(opts, :pipeline_ref, default_pipeline_ref()),
       declared_target_profile: "cumac_scheduler_clean_room_runtime_v1",
       rollback_target: Keyword.get(opts, :rollback_target, :cpu_scheduler),
       failure_domain: :cell_group,
       support_posture: :bounded_clean_room_runtime,
       opts: opts,
       status: :active
     }}
  end

  @impl true
  def plan_slot(slot_context, opts) do
    frame = Map.get(slot_context, :frame, 0)
    slot = Map.get(slot_context, :slot, 0)
    metadata = Map.get(slot_context, :metadata, %{})
    pipeline_ref = Keyword.get(opts, :pipeline_ref, default_pipeline_ref(frame, slot))

    %SlotPlan{
      scheduler: :cumac_scheduler,
      slot_ref: %{frame: frame, slot: slot},
      ue_allocations: Map.get(slot_context, :ue_allocations, []),
      fapi_messages: Map.get(slot_context, :fapi_messages, default_fapi_messages(frame, slot)),
      metadata:
        Map.merge(metadata, %{
          ue_ref: Map.get(slot_context, :ue_ref),
          scheduler_mode: :cumac_contract_host,
          pipeline_ref: pipeline_ref,
          replay_token: "cumac-#{frame}-#{slot}",
          external_acceleration: true,
          declared_target_profile: "cumac_scheduler_clean_room_runtime_v1",
          rollback_target: Keyword.get(opts, :rollback_target, :cpu_scheduler),
          failure_domain: :cell_group,
          support_posture: :bounded_clean_room_runtime
        }),
      status: :planned
    }
  end

  @impl true
  def quiesce(_session, _opts), do: :ok

  @impl true
  def resume(_session), do: :ok

  @impl true
  def terminate(_session), do: :ok

  defp default_fapi_messages(frame, slot) do
    [
      %{
        kind: :dl_tti_request,
        payload: %{frame: frame, slot: slot, grants: [], scheduler: :cumac_scheduler}
      },
      %{
        kind: :ul_tti_request,
        payload: %{frame: frame, slot: slot, grants: [], scheduler: :cumac_scheduler}
      },
      %{
        kind: :ul_dci_request,
        payload: %{frame: frame, slot: slot, grants: [], scheduler: :cumac_scheduler}
      }
    ]
  end

  defp default_pipeline_ref, do: "cumac-bootstrap"
  defp default_pipeline_ref(frame, slot), do: "cumac-bootstrap-#{frame}-#{slot}"
end
