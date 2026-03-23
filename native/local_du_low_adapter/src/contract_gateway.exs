Code.require_file("../../common/contract_gateway/handler.exs", __DIR__)
Code.require_file("../../common/contract_gateway/transport_lifecycle.exs", __DIR__)
Code.require_file("../../common/contract_gateway/runtime.exs", __DIR__)
Code.require_file("./device_session.exs", __DIR__)
Code.require_file("./transport_probe.exs", __DIR__)
Code.require_file("./transport_worker.exs", __DIR__)
Code.require_file("./handler.exs", __DIR__)

defmodule LocalDuLowAdapter.ContractGateway do
  def main do
    NativeContractGateway.Runtime.run(%{
      handler: LocalDuLowAdapter.Handler,
      supported_profile: "local_fapi_profile",
      worker_kind: "local_du_low_contract_gateway"
    })
  end
end
