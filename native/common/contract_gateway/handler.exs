defmodule NativeContractGateway.Handler do
  @type callback_result :: {:ok, map(), map()} | {:error, term()} | {:error, term(), map()}

  @callback initial_state() :: map()
  @callback on_open_session(map(), map()) :: callback_result()
  @callback on_activate_cell(map(), map()) :: callback_result()
  @callback on_submit_slot(map(), map()) :: callback_result()
  @callback on_health_check(map()) :: map()
  @callback on_uplink_indication(map(), map()) :: callback_result()
  @callback on_quiesce(map(), map()) :: callback_result()
  @callback on_resume(map(), map()) :: callback_result()
  @callback on_terminate(map(), map()) :: callback_result()
end
