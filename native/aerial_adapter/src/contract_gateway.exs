Code.require_file("../../common/contract_gateway/handler.exs", __DIR__)
Code.require_file("../../common/contract_gateway/transport_lifecycle.exs", __DIR__)
Code.require_file("../../common/contract_gateway/runtime.exs", __DIR__)
Code.require_file("./device_session.exs", __DIR__)
Code.require_file("./execution_probe.exs", __DIR__)
Code.require_file("./execution_worker.exs", __DIR__)
Code.require_file("./handler.exs", __DIR__)

defmodule AerialAdapter.ContractGateway do
  def main do
    NativeContractGateway.Runtime.run(%{
      handler: AerialAdapter.Handler,
      supported_profile: "aerial_fapi_profile",
      worker_kind: "aerial_contract_gateway"
    })
  end
end
