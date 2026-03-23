defmodule RanTestSupport do
  @moduledoc """
  Test fixtures and helpers for contract and integration work.
  """

  alias RanActionGateway.Change
  alias RanFapiCore.IR

  @spec sample_change() :: Change.t()
  def sample_change do
    %Change{
      scope: "cell_group",
      cell_group: "cg-001",
      target_backend: :stub_fapi_profile,
      change_id: "chg-sample-001",
      reason: "bootstrap",
      idempotency_key: "sample-change-001"
    }
  end

  @spec sample_ir() :: IR.t()
  def sample_ir do
    %IR{
      cell_group_id: "cg-001",
      frame: 0,
      slot: 0,
      profile: :stub_fapi_profile,
      messages: [%{kind: :dl_tti_request, payload: %{}}]
    }
  end
end
