defmodule RanObservability do
  @moduledoc """
  Artifact and telemetry boundary for runtime and operations evidence.
  """

  @spec artifact_root() :: String.t()
  def artifact_root, do: "artifacts"
end
