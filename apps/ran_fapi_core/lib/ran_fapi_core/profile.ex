defmodule RanFapiCore.Profile do
  @moduledoc """
  Supported southbound profiles for bootstrap work.
  """

  alias RanFapiCore.Backends.{AerialBackend, LocalDuLowBackend, StubBackend}

  @profiles [:stub_fapi_profile, :local_fapi_profile, :aerial_fapi_profile]
  @backend_modules %{
    stub_fapi_profile: StubBackend,
    local_fapi_profile: LocalDuLowBackend,
    aerial_fapi_profile: AerialBackend
  }

  @spec all() :: [atom()]
  def all, do: @profiles

  @spec default() :: atom()
  def default, do: :stub_fapi_profile

  @spec backend_module(atom()) :: {:ok, module()} | {:error, :unsupported_profile}
  def backend_module(profile) do
    case Map.fetch(@backend_modules, profile) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unsupported_profile}
    end
  end

  @spec capabilities(atom()) :: {:ok, RanFapiCore.Capability.t()} | {:error, :unsupported_profile}
  def capabilities(profile) do
    with {:ok, module} <- backend_module(profile) do
      {:ok, module.capabilities()}
    end
  end
end
