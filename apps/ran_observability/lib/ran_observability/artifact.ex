defmodule RanObservability.Artifact do
  @moduledoc """
  Artifact bundle metadata for incidents and change verification.
  """

  @enforce_keys [:kind, :path]
  defstruct [:kind, :path, metadata: %{}]

  @type t :: %__MODULE__{
          kind: atom(),
          path: String.t(),
          metadata: map()
        }
end
