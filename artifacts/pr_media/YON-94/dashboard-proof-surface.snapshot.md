# YON-94 Dashboard Proof Surface Snapshot

- URL: http://127.0.0.1:4050/
- Required sections: Proof Surface, Protocol State, Counter Provenance, Claim Cross-check, Replay Drilldowns

```text
R
Mission
Runtime
Agents
Evidence
RAN
OPS
WORKSPACE
RAN Symphony

One operating surface for DU, RIC, agents, and changeflow.

MISSIONS
cg-001
stub_fapi_profile / cpu_scheduler
freeze active / drain draining
0 linked runtime surfaces
repo-local OAI observe running
7 protocol states / 11 counters
RUNS
chg-oai-observe-001
observe / observed
2026-03-28T16:41:39Z
chg-contract-001
verify / verified
2026-03-28T16:41:39Z
SKILL STACK
ran-capture-artifacts
1 scripts / 1 refs
ran-drain-cell-group
1 scripts / 0 refs
ran-freeze-attaches
1 scripts / 0 refs
ran-observe
1 scripts / 1 refs
ran-restart-fapi-gateway
1 scripts / 0 refs
ran-rollback-change
1 scripts / 1 refs
ran-switch-l1-backend
1 scripts / 1 refs
RUNTIME, AGENTS, CHANGES, AND EVIDENCE IN ONE SURFACE / CG-001
RAN Mission Control
snapshot 2026-03-28T16:42:38Z
Refresh
RUN BRIEF
cg-001 mission orchestration

4 RAN surfaces and 6 agent surfaces are visible. Config profile is lab_single_du_rfsim with validation status ok. Native contract state is visible on 1 recent artifacts. Release readiness is ok with 1 recent bundles. Remote operations recorded 1 host-side runs. Install debugging has 2 recent staged runs. Debug desk sees 1 recent failures. Retention planner sees 0 prune candidates. Proof surfaces cover 1 missions, 11 documented counters, and 4 replay drilldowns. Topology source is /home/mud/code/symphony-workspaces/YON-94/config/lab/topology.single_du.rfsim.json. Latest repo-local OAI observe is running with 3/3 services running and 5 documented token counters. Focused backend is stub_fapi_profile with failover to local_fapi_profile, aerial_fapi_profile.

PROTOCOL STATE
7
COUNTERS
11
REPLAY
4
OAI SERVICES
3
OAI HEALTHY
3
OAI TOKENS
5
OAI LANES
1
RAN RUNTIME
4
AGENT MESH
6
HEALTHY
14
RECENT CHANGES
2
CONTRACTS
1
BUNDLES
1
REMOTE OPS
1
INSTALL LOGS
2
DEBUG FAILURES
1
PRUNE
0
RUN TIMELINE
Plans, applies, verifies, evidence
profile lab_single_du_rfsim
observe
chg-oai-observe-001
cell_group
n/a
n/a
observed
2026-03-28T16:41:39Z
observations
n/a
no next step
verify
chg-contract-001
cell_group
local_du_low_profile
local_du_low
verified
2026-03-28T16:41:39Z
verify
transport_worker
no next step
RUNTIME LANES
RAN fabric and agent mesh
ok
RAN Fabric
4 surfaces
emu-gnb-mono
Up 4 weeks
oai-flexric:dev
compose docker
oai-e2-net
ran-oai-we-flexric-rfsim-local-001
Up 8 days
oaisoftwarealliance/oai-gnb:develop
compose adhoc
host
ran-oai-we-nrue-rfsim-local-001
Up 8 days
oaisoftwarealliance/oai-nr-ue:develop
compose adhoc
host
ran-oai-we-flexric-001
Exited (134) 8 days ago
oaisoftwarealliance/oai-gnb:develop
compose adhoc
host
Agent Mesh
6 surfaces
flexric-timescaledb
Up 5 weeks (healthy)
timescale/timescaledb:latest-pg16
compose vranric_rs
vranric_rs_default
mysql-flexric
Up 4 weeks (healthy)
mysql:8.4
compose docker
oai-e2-net
rustric-xapp
Up 5 weeks (healthy)
vranric_rs-rustric-xapp
compose vranric_rs
vranric_rs_default
emu-du
Up 4 weeks
oai-flexric:dev
compose docker
oai-e2-net
nearRT-RIC
Up 4 weeks
oai-flexric:dev
compose docker
oai-e2-net
xapp-kpm-telemetry
Up 4 weeks
oai-flexric:dev
compose docker
oai-e2-net
DEPLOY STUDIO
Target-host preview and preflight
ok
DEPLOY INPUTS
Repo-local staging first
Generate target-host files into a safe preview root, then move the bundle to the live server.
Deploy profile
Lab Attach :: lab_attach
Stable Ops :: stable_ops
Troubleshoot :: troubleshoot
selected profile :: Stable Ops
Conservative target-host profile with strict host probe, local-first dashboard exposure, and deterministic fetchback.
profile overlays :: layered_config_preview, strict_host_probe, effective_config_export, remote_fetchback
conservative
ssh_tunnel_first
RECOMMENDED FOR
production-like labs
change windows
deterministic rollback drills
PROFILE RUNBOOK
Generate repo-local preview and review effective config.
Set target_host and keep dashboard bound to 127.0.0.1.
Run host preflight before any remote apply.
Ship the bundle only after preflight evidence is clean.
Fetch evidence back after each remote ranctl run.
Bundle tarball
Install root
Config root
Current root
Repo profile
Cell group
DU id
Default backend
Failover target
Scheduler
OAI repo root
DU conf
CUCP conf
CUUP conf
Project name
Fronthaul session
Host interface
Device path
PCI BDF
Dashboard host
Dashboard port
Mix env
Target host
SSH user
SSH port
Remote bundle dir
Remote install root
Remote config root
Remote systemd dir
Strict probe gate
Pull images
safe preview root :: /home/mud/code/symphony-workspaces/YON-94/artifacts/deploy_preview
recommended actions :: preview, review-readiness, preflight, handoff, remote-ranctl, fetchback
recent remote runs :: 1
recent install runs :: 2
Generate Preview
Run Preflight
Reset Defaults
DEPLOY OUTPUT
Waiting for preview
Generate a preview to materialize topology, request, env, and readiness files into repo-local staging.
PROFILE POSTURE
Stable Ops
Conservative target-host profile with strict host probe, local-first dashboard exposure, and deterministic fetchback.
conservative
ssh_tunnel_first
Generate repo-local preview and review effective config.
Set target_host and keep dashboard bound to 127.0.0.1.
Run host preflight before any remote apply.
Ship the bundle only after preflight evidence is clean.
Fetch evidence back after each remote ranctl run.
No bundle discovered yet.
[ok] ran-lab-01 :: precheck
Easy install preview
Stable Ops
Copy
'bin/ran-install' '--deploy-profile' 'stable_ops' '--ssh-user' 'mud' '--ssh-port' '22'
Easy install apply
needs target_host
Copy
Set target_host first to build an executable install command.
Latest debug CLI
failed
Copy
bin/ran-debug-latest --failures-only
Install Debug Index
2
[quick_install] prepared
host=ran-lab-01
profile=stable_ops
readiness=ready_for_preflight
/home/mud/code/symphony-workspaces/YON-94/artifacts/deploy_preview/quick_install/20260323T095333/debug-summary.txt

[ship_bundle] failed
host=ran-lab-02
profile=stable_ops
/home/mud/code/symphony-workspaces/YON-94/artifacts/install_runs/ran-lab-02/20260323T105012-ship/debug-summary.txt
Latest Debug Incident
failed
[ship_bundle] failed
host=ran-lab-02
profile=stable_ops
step=remote_preflight
exit=255
/home/mud/code/symphony-workspaces/YON-94/artifacts/install_runs/ran-lab-02/20260323T105012-ship/debug-summary.txt
OPERATOR COMPOSER
observe
precheck
plan
apply
rollback
capture-artifacts
Observe runtime, inspect evidence, or route the next `ranctl` action from this mission.
No dashboard action has been executed yet.
SUGGESTED SKILLS
ran-capture-artifacts
run.sh
ran-drain-cell-group
run.sh
ran-freeze-attaches
run.sh
ran-observe
run.sh
ran-restart-fapi-gateway
run.sh
ran-rollback-change
run.sh
INSPECTOR
Focused Context
MISSION FOCUS
cg-001
Selected run: chg-oai-observe-001
stub_fapi_profile
cpu_scheduler
docker_compose_rfsim_f1
DU
du-bootstrap-001
Container
emu-gnb-mono
Status
Up 4 weeks
Failover
local_fapi_profile, aerial_fapi_profile
Attach freeze
active
Drain
draining
OAI observe
running
OAI project
ran-oai-du-local-rfsim
Contract worker
n/a
Contract transport
n/a
Contract lane
n/a
Topology
/home/mud/code/symphony-workspaces/YON-94/config/lab/topology.single_du.rfsim.json
PROOF SURFACE
cg-001
Structured operator view for lane state, protocol state, counters, claims, and replay refs.
LANE STATE
6
PROTOCOL
7
COUNTERS
11
CLAIMS
2
REPLAY
4
Repo-local runtime
running
3/3 services running, 3 healthy
CU-CP
running
healthy / oai-cucp / logs ok
CU-UP
running
healthy / oai-cuup / logs ok
DU/CU PROTOCOL STATE
cg-001
Simulation proof and bounded-standards proof stay visually distinct in the focused context.
Repo-local simulation lane
running
Repo-local simulation proof only. Counters are bounded to the current docker logs tail captured by observe, not lifetime totals.
oai_split_rfsim_repo_local_v1
3/3 running
3 healthy
2026-03-28T16:41:39Z
Source: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DU
oai-du :: ran-oai-du-local-rfsim-du
healthy
du
3 documented counters
DOCUMENTED FIELDS
Service
oai-du
Docker Compose service name captured in the observe artifact for this protocol role.
Source: observe_artifact :: runtime.containers[].service_name :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Container state
running
Container runtime state reported by the observe-time runtime inspection.
Source: observe_artifact :: runtime.containers[].status :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Health
healthy
Container health reported by the observe-time runtime inspection.
Source: observe_artifact :: runtime.containers[].health :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Log probe
ok
Whether the observe step successfully captured the current Docker log tail for this service.
Source: docker_logs_tail :: runtime.containers[].log_probe_status :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Log tail lines
2
How many lines from the current log tail were scanned when counters were recorded.
Source: docker_logs_tail :: runtime.containers[].log_tail_line_count :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DOCUMENTED COUNTERS
DU Frame.Slot tokens
2
Counts DU MAC slot-loop tokens in the current Docker log tail.
Source: docker_logs_tail :: token Frame.Slot :: 2000 tail lines :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DU F1 setup responses
0
Counts DU log tokens confirming the CU-CP F1 setup response reached the DU.
Source: docker_logs_tail :: token received F1 Setup Response :: 2000 tail lines :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DU RFsim wait tokens
0
Counts DU log tokens showing the RFsim server loop is waiting for the peer side.
Source: docker_logs_tail :: token Running as server waiting opposite rfsimulators to connect :: 2000 tail lines :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
CU-CP
oai-cucp :: ran-oai-du-local-rfsim-cucp
healthy
cucp
1 documented counters
DOCUMENTED FIELDS
Service
oai-cucp
Docker Compose service name captured in the observe artifact for this protocol role.
Source: observe_artifact :: runtime.containers[].service_name :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Container state
running
Container runtime state reported by the observe-time runtime inspection.
Source: observe_artifact :: runtime.containers[].status :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Health
healthy
Container health reported by the observe-time runtime inspection.
Source: observe_artifact :: runtime.containers[].health :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Log probe
ok
Whether the observe step successfully captured the current Docker log tail for this service.
Source: docker_logs_tail :: runtime.containers[].log_probe_status :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Log tail lines
1
How many lines from the current log tail were scanned when counters were recorded.
Source: docker_logs_tail :: runtime.containers[].log_tail_line_count :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DOCUMENTED COUNTERS
CU-CP F1 setup responses
1
Counts CU-CP log tokens proving the split control plane answered the DU F1 setup.
Source: docker_logs_tail :: token sending F1 Setup Response :: 2000 tail lines :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
CU-UP
oai-cuup :: ran-oai-du-local-rfsim-cuup
healthy
cuup
1 documented counters
DOCUMENTED FIELDS
Service
oai-cuup
Docker Compose service name captured in the observe artifact for this protocol role.
Source: observe_artifact :: runtime.containers[].service_name :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Container state
running
Container runtime state reported by the observe-time runtime inspection.
Source: observe_artifact :: runtime.containers[].status :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Health
healthy
Container health reported by the observe-time runtime inspection.
Source: observe_artifact :: runtime.containers[].health :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Log probe
ok
Whether the observe step successfully captured the current Docker log tail for this service.
Source: docker_logs_tail :: runtime.containers[].log_probe_status :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Log tail lines
1
How many lines from the current log tail were scanned when counters were recorded.
Source: docker_logs_tail :: runtime.containers[].log_tail_line_count :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DOCUMENTED COUNTERS
CU-UP E1 established tokens
1
Counts CU-UP log tokens confirming E1 association with the CU-CP.
Source: docker_logs_tail :: token E1 connection established :: 2000 tail lines :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Bounded standards lane
select a protocol run
Select an observe or verify run with declared protocol evidence to inspect NGAP, F1, E1AP, and attach/session outcomes.
COUNTER PROVENANCE
11 documented counters
Running services
3
Counts currently running repo-local OAI services in the latest observe artifact.
runtime
observe_runtime_aggregate
running_service_count
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Healthy services
3
Counts healthy repo-local OAI services in the latest observe artifact.
runtime
observe_runtime_aggregate
healthy_service_count
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DU Frame.Slot tokens
2
Counts DU MAC slot-loop tokens in the current Docker log tail.
DU
docker_logs_tail
Frame.Slot
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DU F1 setup responses
0
Counts DU log tokens confirming the CU-CP F1 setup response reached the DU.
DU
docker_logs_tail
received F1 Setup Response
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
DU RFsim wait tokens
0
Counts DU log tokens showing the RFsim server loop is waiting for the peer side.
DU
docker_logs_tail
Running as server waiting opposite rfsimulators to connect
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
CU-CP F1 setup responses
1
Counts CU-CP log tokens proving the split control plane answered the DU F1 setup.
CU-CP
docker_logs_tail
sending F1 Setup Response
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
CU-UP E1 established tokens
1
Counts CU-UP log tokens confirming E1 association with the CU-CP.
CU-UP
docker_logs_tail
E1 connection established
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Handshake attempts
2
Counts handshake attempts recorded before the current contract state.
contract
native_contract
handshake_attempts
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/verify/chg-contract-001.json
Queue depth
4
Counts queued work units in the current contract-bearing runtime lane.
contract
native_contract
queue_depth
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/verify/chg-contract-001.json
Deadline misses
2
Counts timing-window misses reported by the current contract-bearing runtime lane.
contract
native_contract
deadline_miss_count
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/verify/chg-contract-001.json
Timing budget us
800
Configured timing budget in microseconds for the current contract-bearing runtime lane.
contract
native_contract
timing_budget_us
source :: /home/mud/code/symphony-workspaces/YON-94/artifacts/verify/chg-contract-001.json
CLAIM CROSS-CHECK
2 claim surfaces
Repo-local OAI RFsim rehearsal lane
running
bounded simulation-only runtime proof
oai_split_rfsim_repo_local_v1
Cross-check the repo-local split CU-CP, CU-UP, and DU lane against the latest observe artifact before implying live-lab proof.
current :: 3/3 services running with 5 documented counters.
LIMITS
No live-lab claim
No real core claim
No RU timing claim
CURRENT REFS
CURRENT OBSERVE ARTIFACT
/home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
CURRENT CONTROL STATE
/home/mud/code/symphony-workspaces/YON-94/artifacts/control_state/cg-001.json
DOCS AND VERIFY REFS
SUPPORT POSTURE
docs/architecture/15-production-control-evidence-and-interoperability-lanes.md
DEBUG WORKFLOW
docs/architecture/14-debug-and-evidence-workflow.md
REPO-LOCAL VERIFY REQUEST
examples/ranctl/verify-oai-du-docker.json
CLI PROOF TEST
apps/ran_action_gateway/test/ran_action_gateway/cli_test.exs
REPO-LOCAL ROLLBACK REQUEST
examples/ranctl/rollback-oai-du-docker.json
CAPTURE EXAMPLE
artifacts/captures/chg-oai-du-001.json
Declared live protocol lane
ok
live-lab validated declared lane
n79_single_ru_single_ue_lab_v1
Cross-check the declared live standards lane against the documented replacement examples before claiming broader interoperability support.
current :: Latest matching remote run is ok on ran-lab-01.
LIMITS
No multi-cell parity claim
No multi-DU parity claim
No broad RU or core profile claim
CURRENT REFS
LATEST MATCHING REMOTE RUN
/home/mud/code/symphony-workspaces/YON-94/artifacts/remote_runs/ran-lab-01/20260323T005029-precheck/result.jsonl
LATEST CONTRACT-BEARING ARTIFACT
/home/mud/code/symphony-workspaces/YON-94/artifacts/verify/chg-contract-001.json
DOCS AND VERIFY REFS
SUPPORT POSTURE
docs/architecture/15-production-control-evidence-and-interoperability-lanes.md
REPLACEMENT TRACK NOTE
subprojects/ran_replacement/task.md
VERIFY ATTACH AND PING EXAMPLE
subprojects/ran_replacement/examples/status/verify-attach-ping-open5gs-n79.status.json
REPLACEMENT EXAMPLE COVERAGE
apps/ran_action_gateway/test/ran_action_gateway/replacement_examples_test.exs
ROLLBACK STATUS EXAMPLE
subprojects/ran_replacement/examples/status/rollback-gnb-cutover-open5gs-n79.status.json
ROLLBACK EVIDENCE EXAMPLE
subprojects/ran_replacement/examples/artifacts/n79-single-ru-single-ue-open5gs-family-v1/rollback-evidence-failed-cutover-open5gs-n79.json
POLICY
ok validation
Profile
lab_single_du_rfsim
Topology source
/home/mud/code/symphony-workspaces/YON-94/config/lab/topology.single_du.rfsim.json
Default backend
stub_fapi_profile
Scheduler adapter
cpu_scheduler
Supported backends
stub_fapi_profile, local_fapi_profile, aerial_fapi_profile
Release readiness
ok
Release unit
bootstrap_source_bundle
Recent bundles
1
Latest bundle
bootstrap-ui-001
Prune candidates
0
Protected refs
1
/home/mud/code/symphony-workspaces/YON-94/artifacts/releases/bootstrap-ui-001/manifest.json
/tmp/bootstrap-ui-001.tar.gz
Retention planner has no pending prune candidates.
No native contract metadata attached to the focused run.
RUN CONTRACT
chg-oai-observe-001
repo-local OAI observe captured runtime state
Command
observe
Status
observed
Phase
observations
Target backend
n/a
Native contract
No native contract data
Rollback from
n/a
Next
none
/home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
REPLAY DRILLDOWNS
4 operator paths
Focused run replay
observed
Re-open the selected change artifact, its source plan, and any rollback or approval refs before mutating the mission.
CHANGE ARTIFACT
/home/mud/code/symphony-workspaces/YON-94/artifacts/observations/chg-oai-observe-001.json
Remote fetchback replay
ok
Review host-side execution, fetched evidence, and the extracted bundle before trusting a remote standards claim.
REMOTE PLAN
/home/mud/code/symphony-workspaces/YON-94/artifacts/remote_runs/ran-lab-01/20260323T005029-precheck/plan.txt
REMOTE RESULT
/home/mud/code/symphony-workspaces/YON-94/artifacts/remote_runs/ran-lab-01/20260323T005029-precheck/result.jsonl
FETCH EXTRACT
/home/mud/code/symphony-workspaces/YON-94/artifacts/remote_runs/ran-lab-01/20260323T005029-precheck/fetch/extracted
Install recovery drilldown
prepared
Review install or ship-bundle transcripts, debug packs, and runbooks before replaying a recovery or rollback step.
INSTALL SUMMARY
/home/mud/code/symphony-workspaces/YON-94/artifacts/deploy_preview/quick_install/20260323T095333/debug-summary.txt
INSTALL GUIDE
/home/mud/code/symphony-workspaces/YON-94/artifacts/deploy_preview/quick_install/20260323T095333/INSTALL.md
Runtime evidence excerpt
available
Open the latest matching runtime log excerpt to confirm that the structured dashboard surface still matches raw evidence.
RUNTIME EVIDENCE
/home/mud/code/symphony-workspaces/YON-94/artifacts/runtime/demo/runtime.log
EVIDENCE
runtime.log
2026-03-28T16:41:39Z
line-1
line-2
line-3
ORCHESTRATION LANES
chg-oai-observe-001
intent
operators and skills issue ranctl actions
plan
changes become plan/apply/verify/rollback artifacts
runtime
OAI, DU split, FlexRIC, and emulators report live state
evidence
logs and captures remain attached to each change
```
