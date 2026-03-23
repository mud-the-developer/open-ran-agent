defmodule NativeContractGateway.Handler do
  @callback initial_state() :: map()
  @callback on_open_session(map(), map()) :: {:ok, map(), map()} | {:error, term()}
  @callback on_activate_cell(map(), map()) :: {:ok, map(), map()} | {:error, term()}
  @callback on_submit_slot(map(), map()) :: {:ok, map(), map()} | {:error, term()}
  @callback on_health_check(map()) :: map()
  @callback on_uplink_indication(map(), map()) :: {:ok, map(), map()} | {:error, term()}
  @callback on_quiesce(map(), map()) :: {:ok, map(), map()} | {:error, term()}
  @callback on_resume(map(), map()) :: {:ok, map(), map()} | {:error, term()}
  @callback on_terminate(map(), map()) :: {:ok, map(), map()} | {:error, term()}
end
