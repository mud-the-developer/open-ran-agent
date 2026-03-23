# Symphony Workflow Skeleton

## Goal

Provide a repo-local workflow description for using Symphony and Codex as orchestration layers without allowing them into runtime hot paths.

## Primary Flows

### Incident Observation

1. Receive incident or degradation signal.
2. Use `ran-observe` to gather current state.
3. Use `ran-capture-artifacts` if evidence is incomplete.
4. Decide whether a planned change is needed.

### Controlled Backend Switch

1. Run `ran-switch-l1-backend` in precheck mode.
2. Generate plan with `change_id` and rollback intent.
3. Obtain explicit approval.
4. Apply through `bin/ranctl`.
5. Verify within the declared `verify_window`.
6. Trigger rollback skill if verification fails.

## Workflow Constraints

- all mutations go through `bin/ranctl`
- approvals are required for destructive or service-affecting actions
- artifact capture is mandatory on failed verification
- no agent logic may enter slot or FAPI hot paths
