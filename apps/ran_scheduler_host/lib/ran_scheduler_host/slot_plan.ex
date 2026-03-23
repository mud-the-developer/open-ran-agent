defmodule RanSchedulerHost.SlotPlan do
  @moduledoc """
  Normalized scheduler output consumed by the DU-high and FAPI-core boundary.
  """

  @enforce_keys [:scheduler, :slot_ref, :ue_allocations, :fapi_messages, :metadata, :status]
  defstruct [:scheduler, :slot_ref, :ue_allocations, :fapi_messages, :metadata, :status]

  @type slot_ref :: %{
          frame: non_neg_integer(),
          slot: non_neg_integer()
        }

  @type t :: %__MODULE__{
          scheduler: atom(),
          slot_ref: slot_ref(),
          ue_allocations: [map()],
          fapi_messages: [map()],
          metadata: map(),
          status: atom()
        }
end
