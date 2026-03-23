# Repository Rules

- Keep slot and FAPI hot paths free of agent or LLM logic.
- Route all mutating operational actions through `bin/ranctl`.
- Require an explicit approval gate for destructive actions and backend switchovers.
- Update architecture docs or ADRs when interfaces or boundaries change.
- Prefer documentation and contracts before runtime implementation.
- Keep BEAM, native RT paths, and ops workflows as separate concerns.
- Mark stubs with TODOs and state the intended future contract.
