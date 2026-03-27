# aerial_adapter

Bounded clean-room runtime worker for the current `Aerial` support lane.

Current contents:

- `bin/contract_gateway`: executable Port worker used by `aerial_fapi_profile`
- `src/contract_gateway.exs`: adapter-local runtime entrypoint
- shared lifecycle contract only
- no vendor runtime assumptions

Current support posture:

- declared target profile: `aerial_clean_room_runtime_v1`
- verify evidence: `apps/ran_fapi_core/test/ran_fapi_core/native_gateway_contract_test.exs`
  and `apps/ran_fapi_core/test/ran_fapi_core/native_gateway_transport_state_test.exs`
- rollback evidence: the same gateway-session drain, resume, and restart tests
- health and failure-domain refs: `docs/architecture/03-failure-domains.md`
  and `docs/architecture/04-du-high-southbound-contract.md`

Rules:

- do not assume vendor internals here
- implement only the shared canonical backend contract
- keep vendor-specific behavior behind the native adapter boundary
- keep vendor-backed expansion separate from the current clean-room runtime
  support lane

Current non-claims:

- no vendor device bring-up claim
- no attach-plus-ping proof claim
- no production timing guarantee claim
