defmodule RanFapiCore.IR do
  @moduledoc """
  Versioned canonical IR for DU-high southbound intent.
  """

  @enforce_keys [:cell_group_id, :frame, :slot, :profile, :messages]
  defstruct [
    :cell_group_id,
    :ue_ref,
    :frame,
    :slot,
    :profile,
    :messages,
    metadata: %{},
    ir_version: "0.1"
  ]

  @type message_kind ::
          :dl_tti_request
          | :tx_data_request
          | :ul_tti_request
          | :ul_dci_request
          | :slot_indication
          | :rx_data_indication

  @type t :: %__MODULE__{
          cell_group_id: RanCore.cell_group_id(),
          ue_ref: RanCore.ue_ref() | nil,
          frame: non_neg_integer(),
          slot: non_neg_integer(),
          profile: RanCore.backend_profile(),
          messages: [map()],
          metadata: map(),
          ir_version: String.t()
        }

  @valid_message_kinds [
    :dl_tti_request,
    :tx_data_request,
    :ul_tti_request,
    :ul_dci_request,
    :slot_indication,
    :rx_data_indication
  ]

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = ir) do
    errors =
      []
      |> require(ir.cell_group_id, :missing_cell_group_id)
      |> require(is_integer(ir.frame) and ir.frame >= 0, :invalid_frame)
      |> require(is_integer(ir.slot) and ir.slot >= 0, :invalid_slot)
      |> require(is_list(ir.messages) and ir.messages != [], :missing_messages)
      |> validate_messages(ir.messages)

    case errors do
      [] -> :ok
      _ -> {:error, {:invalid_ir, Enum.reverse(errors)}}
    end
  end

  @spec message_kinds(t()) :: [message_kind()]
  def message_kinds(%__MODULE__{} = ir) do
    Enum.map(ir.messages, fn message -> Map.get(message, :kind) || Map.get(message, "kind") end)
  end

  defp require(errors, value, _reason) when value not in [nil, false, ""], do: errors
  defp require(errors, _value, reason), do: [reason | errors]

  defp validate_messages(errors, messages) do
    Enum.reduce(messages, errors, fn message, acc ->
      kind = Map.get(message, :kind) || Map.get(message, "kind")
      payload = Map.get(message, :payload) || Map.get(message, "payload")

      cond do
        kind not in @valid_message_kinds -> [{:unsupported_message_kind, kind} | acc]
        not is_map(payload) -> [{:invalid_message_payload, kind} | acc]
        true -> acc
      end
    end)
  end
end
