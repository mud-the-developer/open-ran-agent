defmodule RanActionGateway do
  @moduledoc """
  Operational change boundary used by `bin/ranctl`.
  """

  alias RanActionGateway.Change

  @spec new_change(map()) :: Change.t()
  def new_change(attrs) do
    struct!(Change, attrs)
  end
end
