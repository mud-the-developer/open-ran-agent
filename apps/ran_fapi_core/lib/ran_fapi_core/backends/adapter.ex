defmodule RanFapiCore.Backends.Adapter do
  @moduledoc """
  Minimum backend contract shared by local, stub, and future Aerial profiles.
  """

  alias RanFapiCore.IR

  @callback capabilities() :: RanFapiCore.Capability.t()
  @callback open_session(keyword()) :: {:ok, term()} | {:error, term()}
  @callback activate_cell(term(), keyword()) :: :ok | {:error, term()}
  @callback submit_slot(term(), IR.t()) :: :ok | {:error, term()}
  @callback handle_uplink_indication(term(), map()) :: :ok | {:error, term()}
  @callback health(term()) :: {:ok, RanFapiCore.Health.t()} | {:error, term()}
  @callback quiesce(term(), keyword()) :: :ok | {:error, term()}
  @callback resume(term()) :: :ok | {:error, term()}
  @callback terminate(term()) :: :ok | {:error, term()}
end
