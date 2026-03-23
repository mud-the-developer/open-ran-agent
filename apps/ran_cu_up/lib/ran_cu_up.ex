defmodule RanCuUp do
  @moduledoc """
  Bootstrap boundary for CU-UP responsibilities.
  """

  @spec start_tunnel(String.t(), map()) :: {:ok, map()}
  def start_tunnel(tunnel_id, attrs \\ %{}) do
    {:ok, Map.put(attrs, :tunnel_id, tunnel_id)}
  end
end
