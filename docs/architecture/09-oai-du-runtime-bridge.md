# OAI DU Runtime Bridge

## Role

`ranctl` now includes a deterministic runtime bridge for OpenAirInterface DU bring-up. The bridge does not move slot-timed work into the BEAM. It only:

- resolves an OAI runtime spec from `cell_group` defaults and request metadata
- optionally validates repo-local UE/core/session rehearsal evidence through `metadata.oai_simulation`
- renders a generated Docker Compose asset under `artifacts/runtime/<change_id>/`
- overlays deterministic bridge networks so upstream OAI example confs can run without editing them in place
- starts or stops an external OAI stack through `docker compose`
- lints mounted OAI conf files for expected split and RFsim markers
- optionally launches one `OAI NR UE` container when `metadata.oai_runtime.ue_conf_path` is present
- captures logs and container state for verify and rollback
- surfaces simulation-only attach, registration, session, and ping evidence refs without promoting them to live-lab proof

## Scope

The first executable path is intentionally narrow:

- RFsim only
- F1 split only
- `CUCP + CUUP + DU`
- optional `OAI NR UE` on the same RFsim lane
- official Docker images
- user-provided or repo-default OAI conf files used as inputs for generated overlay confs
- generated overlay confs mounted read-only into the runtime containers
- optional repo-local UE and simulated-core evidence files for reviewer-facing rehearsal proof

This is a bridge to get a real DU process up from an OAI config with minimal repo-local runtime code.

The bridge now has a similar split to the native contract gateways: shared runtime concerns stay in the common Port/runtime layer, while adapter-local behavior stays in the adapter-specific handlers. In both cases, the boundary is deliberate: shared code owns deterministic framing and lifecycle wiring, while adapter-local code owns the runtime-specific transport/session signals and health surface.

## Request Model

Runtime orchestration is opt-in through `metadata.oai_runtime`, and runtime-enabled lifecycle commands must also carry `metadata.runtime_contract`.

Repo-local rehearsal proof is opt-in through `metadata.oai_simulation`. It never claims live-lab parity. Its only job is to keep UE attach plus simulated core/session evidence reviewer-visible while the lane is still bounded to RFsim.

Repo-visible UE runtime bring-up is separately opt-in through `metadata.oai_runtime.ue_conf_path`. That path launches a bounded `OAI NR UE` beside the split stack so attach or registration failures can be isolated to a concrete runtime or protocol step.

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
    "runtime_contract": {
      "version": "ranctl.runtime.v1",
      "release_unit": "bootstrap_source_bundle",
      "release_ref": "source-checkout@cg-001",
      "entrypoint": "bin/ranctl",
      "runtime_mode": "docker_compose_rfsim_f1"
    },
    "oai_runtime": {
      "repo_root": "examples/oai",
      "du_conf_path": "examples/oai/gnb-du.sa.band78.106prb.rfsim.conf.example",
      "cucp_conf_path": "examples/oai/gnb-cucp.sa.f1.conf.example",
      "cuup_conf_path": "examples/oai/gnb-cuup.sa.f1.conf.example",
      "project_name": "ran-oai-du-cg-001",
      "pull_images": true
    },
    "oai_simulation": {
      "ue_conf_path": "examples/oai/nrue-rfsim-public.conf.example",
      "attach_evidence_path": "examples/oai/simulation/attach.json",
      "registration_evidence_path": "examples/oai/simulation/registration.json",
      "session_evidence_path": "examples/oai/simulation/session.json",
      "ping_evidence_path": "examples/oai/simulation/ping.json"
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
- `artifacts/runtime/<change_id>/conf/ue.conf` when `metadata.oai_runtime.ue_conf_path` is present

The plan artifact also persists a `runtime_contract` snapshot with the requested contract fields, the resolved runtime mode, a deterministic runtime digest, and the current release-readiness snapshot. `apply`, `verify`, and `rollback` compare the current request against that planned snapshot before they touch runtime actions.

`verify` and `capture-artifacts` also write:

- `artifacts/runtime/<change_id>/logs/<container>.log`

When `metadata.oai_simulation` is present, `verify` and `capture-artifacts` also surface:

- `simulation_lane` metadata on the command result
- top-level `attach_status`, `registration_status`, `session_status`, and `ping_status`
- `bundle.runtime.simulation.*` refs inside the capture bundle

The generated Compose asset uses absolute host paths for these overlay confs so the same plan artifact can be re-applied deterministically.

## Runtime Checks

`precheck` adds runtime checks for:

- presence and compatibility of `metadata.runtime_contract`
- docker CLI availability
- docker daemon reachability
- OAI repo root presence
- DU, CUCP, and CUUP conf presence
- gNB image presence
- CUUP image presence or allowed pull-on-apply
- UE image presence or allowed pull-on-apply when `ue_conf_path` is present
- DU conf declares `tr_n_preference = "f1"`
- DU conf declares an `rfsimulator` stanza
- CUCP conf declares `tr_s_preference = "f1"`
- CUUP conf declares `gNB_CU_UP_ID`
- UE conf presence, `/dev/net/tun`, `uicc0`, `pdu_sessions`, and `rfsimulator` markers when `ue_conf_path` is present
- DU conf exposes patch points for `local_n_address` and `remote_n_address`
- CUCP conf exposes patch points for `local_s_address`, `ipv4_cucp`, and `GNB_IPV4_ADDRESS_FOR_NG_AMF`
- CUUP conf exposes patch points for `local_s_address`, `remote_s_address`, `ipv4_cucp`, `ipv4_cuup`, `GNB_IPV4_ADDRESS_FOR_NG_AMF`, and `GNB_IPV4_ADDRESS_FOR_NGU`
- UE conf presence plus `imsi` and `pdu_sessions` declarations when `metadata.oai_simulation` is present
- attach, registration, session, and ping evidence file readiness when `metadata.oai_simulation` is present

If any required patch point is missing, `plan` fails with `runtime_conf_patch_failed` instead of mutating the source conf in place or generating an ambiguous runtime overlay.

## Using Your Own Conf

To run against a local OAI conf set, point `metadata.oai_runtime.du_conf_path`, `cucp_conf_path`, and `cuup_conf_path` at your files.

To launch the bounded split + UE lane, also set `metadata.oai_runtime.ue_conf_path`. The committed repo-local flow uses:

- `examples/oai/gnb-du.sa.band78.106prb.rfsim.conf.example`
- `examples/oai/gnb-cucp.sa.f1.conf.example`
- `examples/oai/gnb-cuup.sa.f1.conf.example`
- `examples/oai/nrue-rfsim-public.conf.example`

and the request set:

- `examples/ranctl/precheck-oai-du-ue-repo-local.json`
- `examples/ranctl/apply-oai-du-ue-repo-local.json`
- `examples/ranctl/verify-oai-du-ue-repo-local.json`
- `examples/ranctl/rollback-oai-du-ue-repo-local.json`

The repo-local public examples already point at `examples/oai/*.example` so the documented RFsim split lane can be exercised from the checkout without `/opt/openairinterface5g`.

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
- UE log contains the tunnel-configuration marker when the UE lane completes registration/session setup

This matters for long-running containers where startup strings may have rotated out of the captured tail but the DU is still clearly active.

This is enough to prove DU process bring-up, split control-plane wiring, and a repo-visible OAI UE launch path. It is not, by itself, a full attach-path success claim: if no reachable AMF/core is present, `verify` still captures the CUCP and UE logs so the failure can be pinned to NGAP/registration rather than generic setup.
When `metadata.oai_simulation` is present, `verify` also exposes:

- UE attach evidence ref
- registration evidence ref
- session evidence ref
- ping evidence ref

These simulation refs are intentionally tagged as `repo_local_simulation` and `live_lab_claim=false`. They are rehearsal proof only, not a replacement for real-core or live-lab evidence.

## Deferred Work

- source-built `nr-softmodem` path alongside Docker
- real core or AMF readiness verification beyond the current repo-local blocker capture
- bundled core bring-up plus attach/ping success verification beyond the repo-local rehearsal lane
- config linting for OAI-specific address mismatches beyond the current split and RFsim markers
- support for USRP and 7.2x FH profiles
