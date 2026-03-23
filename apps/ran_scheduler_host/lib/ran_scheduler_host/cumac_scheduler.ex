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
      status: :bootstrap
    }
  end

  @impl true
  def init_session(opts) do
    {:ok,
     %{
       adapter: :cumac_scheduler,
       pipeline_ref: Keyword.get(opts, :pipeline_ref, default_pipeline_ref()),
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
          external_acceleration: true
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
