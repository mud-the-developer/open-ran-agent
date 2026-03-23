defmodule RanCuCp do
  @moduledoc """
  Bootstrap boundary for CU-CP responsibilities.
  """

  @spec start_association(String.t(), map()) :: {:ok, map()}
  def start_association(association_id, attrs \\ %{}) do
    {:ok, Map.put(attrs, :association_id, association_id)}
  end
end
