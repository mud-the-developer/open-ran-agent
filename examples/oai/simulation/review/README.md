# OAI RFsim Simulation Review Bundle

These checked-in files mirror the reviewer-facing surfaces that
`bin/ranctl verify` and `bin/ranctl capture-artifacts` expose for the public
RFsim + UE-sim request set:

- `examples/ranctl/precheck-oai-du-docker.json`
- `examples/ranctl/apply-oai-du-docker.json`
- `examples/ranctl/verify-oai-du-docker.json`
- `examples/ranctl/rollback-oai-du-docker.json`

The bundle is intentionally bounded to repo-local simulation proof. None of the
refs below imply live-lab validation.

Expected reviewer-visible surfaces:

```text
verify.artifacts
  examples/oai/simulation/attach.json
  examples/oai/simulation/registration.json
  examples/oai/simulation/session.json
  examples/oai/simulation/ping.json

capture-artifacts.bundle.review
  examples/oai/simulation/review/request.json
  examples/oai/simulation/review/compare-report.json
  examples/oai/simulation/review/rollback-evidence.json
```

Use these files when reviewing the simulation lane without opening generated
`artifacts/` output from a local run.
