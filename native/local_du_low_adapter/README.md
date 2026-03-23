# local_du_low_adapter

Native bootstrap contract worker for the repository-owned DU-low / low-PHY integration path.

Current contents:

- `bin/contract_gateway`: executable Port worker used by `local_fapi_profile`
- `src/contract_gateway.exs`: adapter-local runtime entrypoint
- contract-only session lifecycle with drain, resume, uplink indication, and health reporting
- no live PHY, RU, or timing code yet

Design constraints:

- must implement the shared backend contract
- must be controllable through `ranctl`
- must support controlled drain and rollback semantics
