defmodule RanFapiCore.PortProtocol do
  @moduledoc """
  Length-prefixed wire framing for the BEAM-to-native gateway contract.
  """

  @protocol_version "0.1"
  @message_types ~w(
    open_session
    activate_cell
    submit_slot_batch
    uplink_indication
    health_check
    quiesce
    resume
    terminate
  )

  @type wire_message :: %{
          required(String.t()) => String.t() | map() | nil
        }

  @spec new_message(String.t(), map()) :: wire_message()
  def new_message(message_type, attrs \\ %{}) when is_binary(message_type) and is_map(attrs) do
    if message_type in @message_types do
      %{
        "message_type" => message_type,
        "protocol_version" => @protocol_version,
        "cell_group_id" => Map.get(attrs, "cell_group_id"),
        "session_ref" => Map.get(attrs, "session_ref"),
        "trace_id" => Map.get(attrs, "trace_id"),
        "payload" => Map.get(attrs, "payload", %{})
      }
    else
      raise ArgumentError, "unsupported message type #{inspect(message_type)}"
    end
  end

  @spec encode(wire_message()) :: binary()
  def encode(message) when is_map(message) do
    payload = JSON.encode!(message)
    <<byte_size(payload)::unsigned-big-32, payload::binary>>
  end

  @spec decode(binary()) :: {:ok, wire_message(), binary()} | :more | {:error, term()}
  def decode(buffer) when byte_size(buffer) < 4, do: :more

  def decode(<<length::unsigned-big-32, rest::binary>>) when byte_size(rest) < length, do: :more

  def decode(<<length::unsigned-big-32, payload::binary-size(length), rest::binary>>) do
    case JSON.decode(payload) do
      {:ok, message} when is_map(message) -> {:ok, message, rest}
      {:ok, _message} -> {:error, :invalid_wire_message}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version
end
