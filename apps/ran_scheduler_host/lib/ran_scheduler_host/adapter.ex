defmodule RanSchedulerHost.Adapter do
  @moduledoc """
  Behaviour implemented by scheduler backends.
  """

  @callback capabilities() :: map()
  @callback init_session(keyword()) :: {:ok, term()} | {:error, term()}
  @callback plan_slot(map(), keyword()) :: map()
  @callback quiesce(term(), keyword()) :: :ok | {:error, term()}
  @callback resume(term()) :: :ok | {:error, term()}
  @callback terminate(term()) :: :ok | {:error, term()}
end
