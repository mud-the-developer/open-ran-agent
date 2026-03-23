defmodule RanFapiCore.PortProtocolTest do
  use ExUnit.Case, async: true

  alias RanFapiCore.PortProtocol

  test "encode and decode round-trip a framed message" do
    message =
      PortProtocol.new_message("health_check", %{
        "cell_group_id" => "cg-001",
        "session_ref" => "sess-1",
        "trace_id" => "trace-1",
        "payload" => %{"detail" => "full"}
      })

    encoded = PortProtocol.encode(message)

    assert {:ok, decoded, ""} = PortProtocol.decode(encoded)
    assert decoded["message_type"] == "health_check"
    assert decoded["payload"]["detail"] == "full"
    assert decoded["protocol_version"] == PortProtocol.protocol_version()
  end
end
