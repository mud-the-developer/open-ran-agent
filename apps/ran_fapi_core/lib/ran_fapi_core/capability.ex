defmodule RanFapiCore.Capability do
  @moduledoc """
  Normalized backend capability declaration for DU-high southbound negotiation.
  """

  @enforce_keys [:profile, :supported_message_kinds, :max_cell_groups, :timing_model, :status]
  defstruct [
    :profile,
    :supported_message_kinds,
    :max_cell_groups,
    :timing_model,
    :status,
    supported_profiles: [],
    drain_support: false,
    rollback_support: false,
    artifact_capture_support: false,
    supported_health_states: [:healthy, :degraded, :draining, :failed],
    metadata: %{}
  ]

  @type health_state :: :healthy | :degraded | :draining | :failed

  @type t :: %__MODULE__{
          profile: RanCore.backend_profile(),
          supported_profiles: [RanCore.backend_profile()],
          supported_message_kinds: [RanFapiCore.IR.message_kind()],
          max_cell_groups: pos_integer(),
          timing_model: atom(),
          drain_support: boolean(),
          rollback_support: boolean(),
          artifact_capture_support: boolean(),
          supported_health_states: [health_state()],
          status: atom(),
          metadata: map()
        }

  @default_message_kinds [
    :dl_tti_request,
    :tx_data_request,
    :ul_tti_request,
    :ul_dci_request,
    :slot_indication,
    :rx_data_indication
  ]

  @spec normalize!(map()) :: t()
  def normalize!(attrs) when is_map(attrs) do
    profile = Map.fetch!(attrs, :profile)

    %__MODULE__{
      profile: profile,
      supported_profiles: Map.get(attrs, :supported_profiles, [profile]),
      supported_message_kinds: Map.get(attrs, :supported_message_kinds, @default_message_kinds),
      max_cell_groups: Map.get(attrs, :max_cell_groups, 1),
      timing_model: Map.get(attrs, :timing_model, :slot_batch),
      drain_support: Map.get(attrs, :drain_support, false),
      rollback_support: Map.get(attrs, :rollback_support, false),
      artifact_capture_support: Map.get(attrs, :artifact_capture_support, false),
      supported_health_states:
        Map.get(attrs, :supported_health_states, [:healthy, :degraded, :draining, :failed]),
      status: Map.get(attrs, :status, :placeholder),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @spec compatible?(t(), RanCore.backend_profile(), [RanFapiCore.IR.message_kind()]) ::
          :ok | {:error, atom()}
  def compatible?(%__MODULE__{} = capability, profile, message_kinds) do
    cond do
      profile not in capability.supported_profiles ->
        {:error, :unsupported_profile}

      not Enum.all?(message_kinds, &(&1 in capability.supported_message_kinds)) ->
        {:error, :unsupported_message_kind}

      true ->
        :ok
    end
  end
end
