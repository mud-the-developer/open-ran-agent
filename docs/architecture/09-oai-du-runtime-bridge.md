# OAI DU Runtime Bridge

## Role

`ranctl` now includes a deterministic runtime bridge for OpenAirInterface DU bring-up. The bridge does not move slot-timed work into the BEAM. It only:

- resolves an OAI runtime spec from `cell_group` defaults and request metadata
- renders a generated Docker Compose asset under `artifacts/runtime/<change_id>/`
- overlays deterministic bridge networks so upstream OAI example confs can run without editing them in place
- starts or stops an external OAI stack through `docker compose`
- lints mounted OAI conf files for expected split and RFsim markers
- captures logs and container state for verify and rollback

## Scope

The first executable path is intentionally narrow:

- RFsim only
- F1 split only
- `CUCP + CUUP + DU`
- official Docker images
- user-provided or repo-default OAI conf files used as inputs for generated overlay confs
- generated overlay confs mounted read-only into the runtime containers

This is a bridge to get a real DU process up from an OAI config with minimal repo-local runtime code.

The bridge now has a similar split to the native contract gateways: shared runtime concerns stay in the common Port/runtime layer, while adapter-local behavior stays in the adapter-specific handlers. In both cases, the boundary is deliberate: shared code owns deterministic framing and lifecycle wiring, while adapter-local code owns the runtime-specific transport/session signals and health surface.

## Request Model

Runtime orchestration is opt-in through `metadata.oai_runtime`.

```json
{
  "scope": "cell_group",
  "cell_group": "cg-001",
  "change_id": "chg-oai-du-001",
  "reason": "bring up OAI DU in rfsim",
  "idempotency_key": "chg-oai-du-001",
  "approval": {
    "approved": true,
    "approved_by": "operator.oai-runtime",
    "approved_at": "2026-03-21T07:15:00Z",
    "ticket_ref": "CHG-OAI-DU-001",
    "source": "example"
  },
  "verify_window": {
    "duration": "30s",
    "checks": ["gateway_healthy"]
  },
  "metadata": {
    "oai_runtime": {
      "repo_root": "/opt/openairinterface5g",
      "du_conf_path": "/opt/openairinterface5g/ci-scripts/conf_files/gnb-du.sa.band78.106prb.rfsim.conf",
      "cucp_conf_path": "/opt/openairinterface5g/ci-scripts/conf_files/gnb-cucp.sa.f1.conf",
      "cuup_conf_path": "/opt/openairinterface5g/ci-scripts/conf_files/gnb-cuup.sa.f1.conf",
      "project_name": "ran-oai-du-cg-001",
      "pull_images": true
    }
  }
}
```

## Generated Assets

For a runtime-enabled change, `plan` now materializes:

- `artifacts/plans/<change_id>.json`
- `artifacts/runtime/<change_id>/docker-compose.yml`
- `artifacts/runtime/<change_id>/conf/du.conf`
- `artifacts/runtime/<change_id>/conf/cucp.conf`
- `artifacts/runtime/<change_id>/conf/cuup.conf`

`verify` and `capture-artifacts` also write:

- `artifacts/runtime/<change_id>/logs/<container>.log`

The generated Compose asset uses absolute host paths for these overlay confs so the same plan artifact can be re-applied deterministically.

## Runtime Checks

`precheck` adds runtime checks for:

- docker CLI availability
- docker daemon reachability
- OAI repo root presence
- DU, CUCP, and CUUP conf presence
- gNB image presence
- CUUP image presence or allowed pull-on-apply
- DU conf declares `tr_n_preference = "f1"`
- DU conf declares an `rfsimulator` stanza
- CUCP conf declares `tr_s_preference = "f1"`
- CUUP conf declares `gNB_CU_UP_ID`
- DU conf exposes patch points for `local_n_address` and `remote_n_address`
- CUCP conf exposes patch points for `local_s_address`, `ipv4_cucp`, and `GNB_IPV4_ADDRESS_FOR_NG_AMF`
- CUUP conf exposes patch points for `local_s_address`, `remote_s_address`, `ipv4_cucp`, `ipv4_cuup`, `GNB_IPV4_ADDRESS_FOR_NG_AMF`, and `GNB_IPV4_ADDRESS_FOR_NGU`

If any required patch point is missing, `plan` fails with `runtime_conf_patch_failed` instead of mutating the source conf in place or generating an ambiguous runtime overlay.

## Using Your Own Conf

To run against a local OAI conf set, point `metadata.oai_runtime.du_conf_path`, `cucp_conf_path`, and `cuup_conf_path` at your files.

Use [examples/ranctl/apply-oai-du-docker-template.json](https://github.com/mud-the-developer/open-ran-agent/blob/main/examples/ranctl/apply-oai-du-docker-template.json) as the request shape. The bridge will:

- read your source confs as-is
- validate the required split markers and patch points during `precheck`
- generate patched runtime overlay confs under `artifacts/runtime/<change_id>/conf/`
- leave your original conf files unchanged

## Verify Semantics

`verify` remains bounded and deterministic. The current implementation checks:

- each OAI container exists
- each OAI container reports `Running=true`
- each container log tail is capturable
- DU log contains an F1 setup completion marker, or steady-state DU slot activity is present while CUCP shows the F1 setup response
- DU log reaches the main loop marker, or reports steady-state RFsim slot activity
- CUCP log contains an F1 setup response marker
- CUUP log contains an E1 establishment marker

This matters for long-running containers where startup strings may have rotated out of the captured tail but the DU is still clearly active.

This is enough to prove DU process bring-up and split control-plane wiring. It is not yet a full attach-path validation.

## Deferred Work

- source-built `nr-softmodem` path alongside Docker
- CUCP to AMF readiness verification
- UE attach and ping verification
- config linting for OAI-specific address mismatches beyond the current split and RFsim markers
- support for USRP and 7.2x FH profiles
