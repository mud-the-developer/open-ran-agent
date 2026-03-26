# aerial_adapter

Bootstrap clean-room contract worker for the future NVIDIA Aerial integration path.

Current contents:

- `bin/contract_gateway`: executable Port worker used by `aerial_fapi_profile`
- `src/contract_gateway.exs`: adapter-local runtime entrypoint
- shared lifecycle contract only
- no vendor runtime assumptions

Rules:

- do not assume vendor internals here
- implement only the shared canonical backend contract
- keep vendor-specific behavior behind the native adapter boundary
- keep support posture at roadmap-only until target-host proof, verify/rollback evidence,
  and a stable runtime health model exist

Current non-claims:

- no vendor device bring-up claim
- no attach-plus-ping proof claim
- no production timing guarantee claim
