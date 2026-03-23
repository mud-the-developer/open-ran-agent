defmodule RanDuHigh.CellGroup do
  @moduledoc """
  Bootstrap representation of a DU-high cell-group runtime unit.
  """

  @enforce_keys [:id, :backend, :scheduler]
  defstruct [:id, :backend, :scheduler]

  @type t :: %__MODULE__{
          id: String.t(),
          backend: RanCore.backend_profile(),
          scheduler: atom()
        }
end
