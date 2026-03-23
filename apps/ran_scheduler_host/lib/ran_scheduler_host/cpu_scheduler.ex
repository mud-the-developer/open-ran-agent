defmodule RanSchedulerHost.CpuScheduler do
  @moduledoc """
  Placeholder CPU scheduler implementation for the bootstrap phase.
  """

  @behaviour RanSchedulerHost.Adapter
  alias RanSchedulerHost.SlotPlan

  @impl true
  def capabilities do
    %{
      adapter: :cpu_scheduler,
      supports_replay: true,
      supports_external_acceleration: false
    }
  end

  @impl true
  def init_session(opts) do
    {:ok, %{adapter: :cpu_scheduler, opts: opts}}
  end

  @impl true
  def plan_slot(slot_context, _opts) do
    frame = Map.get(slot_context, :frame, 0)
    slot = Map.get(slot_context, :slot, 0)
    metadata = Map.get(slot_context, :metadata, %{})

    %SlotPlan{
      scheduler: :cpu_scheduler,
      slot_ref: %{frame: frame, slot: slot},
      ue_allocations: Map.get(slot_context, :ue_allocations, []),
      fapi_messages: Map.get(slot_context, :fapi_messages, default_fapi_messages(frame, slot)),
      metadata:
        Map.merge(metadata, %{
          ue_ref: Map.get(slot_context, :ue_ref),
          scheduler_mode: :bootstrap_cpu
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
        payload: %{frame: frame, slot: slot, grants: []}
      },
      %{
        kind: :tx_data_request,
        payload: %{frame: frame, slot: slot, pdus: []}
      }
    ]
  end
end
