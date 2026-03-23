defmodule RanCore do
  @moduledoc """
  Shared domain helpers and repository-wide types.
  """

  @type cell_group_id :: String.t()
  @type ue_ref :: String.t()
  @type backend_profile :: :stub_fapi_profile | :local_fapi_profile | :aerial_fapi_profile

  @spec supported_backends() :: [backend_profile()]
  def supported_backends do
    [:stub_fapi_profile, :local_fapi_profile, :aerial_fapi_profile]
  end
end
