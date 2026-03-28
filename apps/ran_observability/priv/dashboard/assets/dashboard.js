const state = {
  data: null,
  focusedCellGroupId: null,
  focusedRunId: null,
  focusedContainerName: null,
  lastAction: null,
  deployForm: null,
  lastDeploy: null
};

const DEPLOY_TEXT_FIELDS = [
  ["bundle_tarball", "Bundle tarball"],
  ["install_root", "Install root"],
  ["etc_root", "Config root"],
  ["current_root", "Current root"],
  ["repo_profile", "Repo profile"],
  ["cell_group", "Cell group"],
  ["du_id", "DU id"],
  ["default_backend", "Default backend"],
  ["failover_target", "Failover target"],
  ["scheduler", "Scheduler"],
  ["oai_repo_root", "OAI repo root"],
  ["du_conf_path", "DU conf"],
  ["cucp_conf_path", "CUCP conf"],
  ["cuup_conf_path", "CUUP conf"],
  ["project_name", "Project name"],
  ["fronthaul_session", "Fronthaul session"],
  ["host_interface", "Host interface"],
  ["device_path", "Device path"],
  ["pci_bdf", "PCI BDF"],
  ["dashboard_host", "Dashboard host"],
  ["dashboard_port", "Dashboard port"],
  ["mix_env", "Mix env"],
  ["target_host", "Target host"],
  ["ssh_user", "SSH user"],
  ["ssh_port", "SSH port"],
  ["remote_bundle_dir", "Remote bundle dir"],
  ["remote_install_root", "Remote install root"],
  ["remote_etc_root", "Remote config root"],
  ["remote_systemd_dir", "Remote systemd dir"]
];
const DEPLOY_BOOL_FIELDS = [
  ["strict_host_probe", "Strict probe gate"],
  ["pull_images", "Pull images"]
];

const byId = (id) => document.getElementById(id);

async function fetchSnapshot() {
  const response = await fetch("/api/dashboard", { cache: "no-store" });

  if (!response.ok) {
    throw new Error(`dashboard snapshot failed: ${response.status}`);
  }

  return response.json();
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function renderLaneNotes(items, emptyMessage) {
  if (!items?.length) {
    return `<div class="lane-note">${escapeHtml(emptyMessage)}</div>`;
  }

  return items.map((item) => `<div class="lane-note">${escapeHtml(item)}</div>`).join("");
}

function renderDeployChecklist(checklist) {
  if (!checklist?.length) {
    return `<div class="empty">No readiness checklist available.</div>`;
  }

  return `
    <div class="deploy-checklist">
      ${checklist
        .map(
          (item) => `
            <div class="deploy-check-item ${escapeHtml(item.status || "unknown")}">
              <div class="deploy-check-top">
                <strong>${escapeHtml(item.label || item.id)}</strong>
                <span class="status-pill ${escapeHtml(item.status || "unknown")}">${escapeHtml(item.status || "unknown")}</span>
              </div>
              <div class="deploy-check-detail">${escapeHtml(item.detail || "No detail available.")}</div>
            </div>
          `
        )
        .join("")}
    </div>
  `;
}

function renderDeployCommandCard(label, status, content, copyTargetId) {
  const commandText = content || "No command surface available yet.";
  return `
    <section class="deploy-preview-card">
      <div class="deploy-preview-header">
        <div class="inspector-row deploy-row"><span>${escapeHtml(label)}</span><strong>${escapeHtml(status)}</strong></div>
        <button class="mini-copy" data-copy-target="${escapeHtml(copyTargetId)}" type="button">Copy</button>
      </div>
      <pre id="${escapeHtml(copyTargetId)}">${escapeHtml(commandText)}</pre>
    </section>
  `;
}

function debugIncidentSummary(incident) {
  if (!incident) {
    return "No recent failed run has been indexed.";
  }

  return [
    `[${incident.kind || "debug"}] ${incident.status || "unknown"}`,
    incident.host ? `host=${incident.host}` : null,
    incident.command ? `command=${incident.command}` : null,
    incident.deploy_profile ? `profile=${incident.deploy_profile}` : null,
    incident.failed_step ? `step=${incident.failed_step}` : null,
    incident.exit_code !== undefined && incident.exit_code !== null ? `exit=${incident.exit_code}` : null,
    incident.summary_path || incident.debug_pack_path || incident.result_path || incident.path || "no path"
  ]
    .filter(Boolean)
    .join("\n");
}

function recentFailureSummary(items) {
  if (!items?.length) {
    return "No recent failed runs indexed.";
  }

  return items
    .slice(0, 5)
    .map((incident) =>
      [
        `[${incident.kind || "debug"}] ${incident.status || "unknown"} :: ${incident.id || "n/a"}`,
        incident.host ? `host=${incident.host}` : null,
        incident.command ? `command=${incident.command}` : null,
        incident.failed_step ? `step=${incident.failed_step}` : null,
        incident.summary_path || incident.debug_pack_path || incident.result_path || incident.path || "no path"
      ]
        .filter(Boolean)
        .join("\n")
    )
    .join("\n\n");
}

async function copyText(text) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const area = document.createElement("textarea");
  area.value = text;
  area.setAttribute("readonly", "true");
  area.style.position = "absolute";
  area.style.left = "-9999px";
  document.body.appendChild(area);
  area.select();
  document.execCommand("copy");
  document.body.removeChild(area);
}

function shellQuote(value) {
  return `'${String(value ?? "").replaceAll("'", `'\"'\"'`)}'`;
}

function runItems(data) {
  const seen = new Set();

  return data.activity.recent_changes.filter((item) => {
    if (seen.has(item.id)) {
      return false;
    }

    seen.add(item.id);
    return true;
  });
}

function findFocusedCellGroup(data) {
  const groups = data.ran.cell_groups || [];

  if (!groups.length) {
    return null;
  }

  return groups.find((group) => group.id === state.focusedCellGroupId) || groups[0];
}

function findFocusedRun(data) {
  const runs = runItems(data);

  if (!runs.length) {
    return null;
  }

  return runs.find((item) => item.id === state.focusedRunId) || runs[0];
}

function findFocusedNativeContract(data, focusedRun) {
  return focusedRun?.native_contract ? focusedRun : null;
}

function groupContainersForMission(data, cellGroup) {
  if (!cellGroup) {
    return data.runtime.containers || [];
  }

  const projectName = currentOaiObservation(cellGroup)?.project_name;

  return (data.runtime.containers || []).filter((container) => {
    const haystack = `${container.name} ${container.compose_project || ""}`.toLowerCase();
    return haystack.includes(cellGroup.id.toLowerCase())
      || (projectName && container.compose_project === projectName);
  });
}

function findFocusedContainer(data, cellGroup) {
  const containers = data.runtime.containers || [];

  if (!containers.length) {
    return null;
  }

  const explicit = containers.find((container) => container.name === state.focusedContainerName);

  if (explicit) {
    return explicit;
  }

  const missionContainers = groupContainersForMission(data, cellGroup);

  return missionContainers[0] || data.runtime.ran_containers?.[0] || containers[0];
}

function findFocusedEvidence(data, cellGroup, run) {
  const evidence = data.runtime.evidence || [];

  if (!evidence.length) {
    return null;
  }

  if (run) {
    const runMatch = evidence.find((item) => item.path.includes(run.id));
    if (runMatch) {
      return runMatch;
    }
  }

  if (cellGroup) {
    const missionMatch = evidence.find((item) => item.path.includes(cellGroup.id));
    if (missionMatch) {
      return missionMatch;
    }
  }

  return evidence[0];
}

function missionRuntimeCount(data, cellGroup) {
  return groupContainersForMission(data, cellGroup).length;
}

function currentOaiObservation(cellGroup) {
  return cellGroup?.oai_observation || null;
}

function roleLabel(role) {
  switch (role) {
    case "du":
      return "DU";
    case "cucp":
      return "CU-CP";
    case "cuup":
      return "CU-UP";
    case "ue":
      return "UE";
    default:
      return role || "service";
  }
}

function renderMissionList(data, cellGroup) {
  const groups = data.ran.cell_groups || [];

  if (!groups.length) {
    byId("mission-list").innerHTML = `<div class="empty">No cell groups configured.</div>`;
    return;
  }

  byId("mission-list").innerHTML = groups
    .map(
      (group) => `
        <button class="mission-item ${group.id === cellGroup?.id ? "active" : ""}" data-cell-group="${escapeHtml(group.id)}" type="button">
          <div class="mission-name">${escapeHtml(group.id)}</div>
          <div class="mission-meta">${escapeHtml(group.backend)} / ${escapeHtml(group.scheduler)}</div>
          <div class="mission-meta">freeze ${escapeHtml(group.control_state?.attach_freeze?.status || "inactive")} / drain ${escapeHtml(group.control_state?.drain?.status || "idle")}</div>
          <div class="mission-meta">${missionRuntimeCount(data, group)} linked runtime surfaces</div>
          <div class="mission-meta">repo-local OAI observe ${escapeHtml(currentOaiObservation(group)?.runtime_state || "not captured")}</div>
        </button>
      `
    )
    .join("");
}

function renderRunList(data, focusedRun) {
  const runs = runItems(data);

  if (!runs.length) {
    byId("run-list").innerHTML = `<div class="empty">No orchestration runs found.</div>`;
    return;
  }

  byId("run-list").innerHTML = runs
    .slice(0, 8)
    .map(
      (item) => `
        <button class="run-item ${item.id === focusedRun?.id ? "active" : ""}" data-run-id="${escapeHtml(item.id)}" type="button">
          <div class="run-title">${escapeHtml(item.id)}</div>
          <div class="run-meta">${escapeHtml(item.command || item.phase || "unknown")} / ${escapeHtml(item.status || "unknown")}</div>
          <div class="run-meta">${escapeHtml(item.updated_at)}</div>
        </button>
      `
    )
    .join("");
}

function renderSkillStack(data) {
  const skills = data.agents.skills || [];

  if (!skills.length) {
    byId("skill-stack").innerHTML = `<div class="empty">No skills discovered.</div>`;
    return;
  }

  byId("skill-stack").innerHTML = skills
    .slice(0, 8)
    .map(
      (skill) => `
        <div class="skill-item">
          <div class="skill-name">${escapeHtml(skill.name)}</div>
          <div class="skill-meta">${skill.script_count} scripts / ${skill.reference_count} refs</div>
        </div>
      `
    )
    .join("");
}

function renderTopbar(data, cellGroup) {
  byId("workspace-kicker").textContent = `${data.identity.subtitle} / ${cellGroup?.id || "unassigned mission"}`;
  byId("workspace-title").textContent = data.identity.title;
  byId("generated-at").textContent = `snapshot ${data.generated_at}`;
}

function renderBrief(data, cellGroup) {
  const observe = currentOaiObservation(cellGroup);

  byId("brief-title").textContent = cellGroup
    ? `${cellGroup.id} mission orchestration`
    : "Mission orchestration";

  byId("brief-summary").textContent = [
    `${data.overview.ran_runtime_count} RAN surfaces and ${data.overview.agent_runtime_count} agent surfaces are visible.`,
    `Config profile is ${data.ran.profile} with validation status ${data.ran.validation.status}.`,
    `Native contract state is visible on ${data.overview.native_contract_count || 0} recent artifacts.`,
    `Release readiness is ${data.release?.readiness?.status || "unknown"} with ${data.overview.recent_bundle_count || 0} recent bundles.`,
    `Remote operations recorded ${data.overview.remote_run_count || 0} host-side runs.`,
    `Install debugging has ${data.overview.install_run_count || 0} recent staged runs.`,
    `Debug desk sees ${data.overview.debug_failure_count || 0} recent failures.`,
    `Retention planner sees ${data.retention?.summary?.prune_count || 0} prune candidates.`,
    data.ran.topology_source
      ? `Topology source is ${data.ran.topology_source}.`
      : "Topology source is the repo default config.",
    observe
      ? `Latest repo-local OAI observe is ${observe.runtime_state} with ${observe.running_service_count}/${observe.service_count} services running and ${observe.token_metric_count} documented token counters.`
      : "No repo-local OAI observe artifact has been captured yet for the focused mission.",
    cellGroup
      ? `Focused backend is ${cellGroup.backend} with failover to ${cellGroup.failover_targets.join(", ") || "none"}.`
      : "No focused cell group is selected."
  ].join(" ");

  const metrics = [
    ["OAI Lanes", data.overview.oai_observation_count || 0],
    ["RAN Runtime", data.overview.ran_runtime_count],
    ["Agent Mesh", data.overview.agent_runtime_count],
    ["Healthy", data.overview.healthy_runtime_count],
    ["Recent Changes", data.overview.recent_change_count],
    ["Contracts", data.overview.native_contract_count || 0],
    ["Bundles", data.overview.recent_bundle_count || 0],
    ["Remote Ops", data.overview.remote_run_count || 0],
    ["Install Logs", data.overview.install_run_count || 0],
    ["Debug Failures", data.overview.debug_failure_count || 0],
    ["Prune", data.overview.prune_candidate_count || 0]
  ];

  if (observe) {
    metrics.unshift(
      ["OAI Services", observe.service_count],
      ["OAI Healthy", observe.healthy_service_count],
      ["OAI Tokens", observe.token_metric_count]
    );
  }

  byId("brief-metrics").innerHTML = metrics
    .map(
      ([label, value]) => `
        <div class="brief-metric">
          <div class="section-kicker">${escapeHtml(label)}</div>
          <div class="brief-metric-value">${escapeHtml(value)}</div>
        </div>
      `
    )
    .join("");
}

function renderTimeline(data, focusedRun) {
  const items = data.activity.recent_changes || [];
  byId("profile-chip").textContent = `profile ${data.ran.profile}`;

  if (!items.length) {
    byId("timeline").innerHTML = `<div class="empty">No timeline artifacts available.</div>`;
    return;
  }

  byId("timeline").innerHTML = items
    .map(
      (item) => `
        <div class="timeline-item ${escapeHtml(item.phase || "")}">
          <div class="timeline-dot"></div>
          <button class="timeline-card ${item.id === focusedRun?.id ? "active" : ""}" data-run-id="${escapeHtml(item.id)}" type="button">
            <div class="timeline-top">
              <div>
                <div class="timeline-title">${escapeHtml(item.command || item.phase || "artifact")}</div>
                <div class="timeline-meta">
                  <span>${escapeHtml(item.id)}</span>
                  <span>${escapeHtml(item.scope || "n/a")}</span>
                  <span>${escapeHtml(item.target_backend || "n/a")}</span>
                  <span>${escapeHtml(item.native_contract?.backend_family || "n/a")}</span>
                </div>
              </div>
              <span class="status-pill ${escapeHtml(item.status || "unknown")}">${escapeHtml(item.status || "unknown")}</span>
            </div>
            <div class="timeline-meta">
              <span>${escapeHtml(item.updated_at)}</span>
              <span>${escapeHtml(item.phase || "unknown")}</span>
              <span>${escapeHtml(item.native_contract?.worker_kind || "n/a")}</span>
              <span>${escapeHtml((item.next || []).join(" -> ") || "no next step")}</span>
            </div>
          </button>
        </div>
      `
    )
    .join("");
}

function runtimeLaneMarkup(title, note, containers, activeName) {
  if (!containers.length) {
    return `
      <section class="runtime-lane">
        <div class="runtime-lane-header">
          <strong>${escapeHtml(title)}</strong>
          <span class="section-note">${escapeHtml(note)}</span>
        </div>
        <div class="empty">No containers discovered.</div>
      </section>
    `;
  }

  return `
    <section class="runtime-lane">
      <div class="runtime-lane-header">
        <strong>${escapeHtml(title)}</strong>
        <span class="section-note">${escapeHtml(note)}</span>
      </div>
      <div class="runtime-stack">
        ${containers
          .map(
            (container) => `
              <button class="runtime-card ${escapeHtml(container.domain)} ${container.name === activeName ? "active" : ""}" data-container-name="${escapeHtml(container.name)}" type="button">
                <div class="runtime-top">
                  <div class="runtime-name">${escapeHtml(container.name)}</div>
                  <span class="status-pill ${escapeHtml(container.tone)}">${escapeHtml(container.status)}</span>
                </div>
                <div class="runtime-meta">
                  <span>${escapeHtml(container.image)}</span>
                  <span>compose ${escapeHtml(container.compose_project || "adhoc")}</span>
                  <span>${escapeHtml((container.networks || []).join(", ") || "host")}</span>
                </div>
              </button>
            `
          )
          .join("")}
      </div>
    </section>
  `;
}

function renderRuntimeBoard(data, focusedContainer) {
  byId("runtime-status-chip").textContent = data.runtime.status;
  byId("runtime-board").innerHTML = [
    runtimeLaneMarkup(
      "RAN Fabric",
      `${data.runtime.ran_containers.length} surfaces`,
      data.runtime.ran_containers || [],
      focusedContainer?.name
    ),
    runtimeLaneMarkup(
      "Agent Mesh",
      `${data.runtime.agent_containers.length} surfaces`,
      data.runtime.agent_containers || [],
      focusedContainer?.name
    )
  ].join("");
}

function ensureDeployForm(snapshot) {
  if (!state.deployForm && snapshot.deploy?.defaults) {
    state.deployForm = { ...snapshot.deploy.defaults };
  }
}

function renderFocusSummary(data, cellGroup, focusedRun, focusedContainer) {
  const target = byId("focus-summary");
  const nativeContractRun = findFocusedNativeContract(data, focusedRun);
  const nativeContract = nativeContractRun?.native_contract || null;
  const observe = currentOaiObservation(cellGroup);

  if (!cellGroup) {
    target.innerHTML = `<div class="empty">No focused mission.</div>`;
    return;
  }

  const tags = [cellGroup.backend, cellGroup.scheduler, cellGroup.runtime_mode || "n/a"];

  if (nativeContract?.backend_family) {
    tags.push(nativeContract.backend_family);
  }

  if (nativeContract?.worker_kind) {
    tags.push(nativeContract.worker_kind);
  }

  if (nativeContract?.transport_worker || nativeContract?.execution_lane) {
    tags.push(nativeContract.transport_worker || nativeContract.execution_lane);
  }

  target.innerHTML = `
    <div class="section-kicker">Mission Focus</div>
    <h4>${escapeHtml(cellGroup.id)}</h4>
    <div class="inspector-meta">Selected run: ${escapeHtml(focusedRun?.id || "none")}</div>
    <div class="focus-tags">
      ${tags.map((tag) => `<span class="runtime-tag">${escapeHtml(tag)}</span>`).join("")}
    </div>
    <div class="inspector-rows">
      <div class="inspector-row"><span>DU</span><strong>${escapeHtml(cellGroup.du)}</strong></div>
      <div class="inspector-row"><span>Container</span><strong>${escapeHtml(focusedContainer?.name || "none")}</strong></div>
      <div class="inspector-row"><span>Status</span><strong>${escapeHtml(focusedContainer?.status || "n/a")}</strong></div>
      <div class="inspector-row"><span>Failover</span><strong>${escapeHtml(cellGroup.failover_targets.join(", ") || "none")}</strong></div>
      <div class="inspector-row"><span>Attach freeze</span><strong>${escapeHtml(cellGroup.control_state?.attach_freeze?.status || "inactive")}</strong></div>
      <div class="inspector-row"><span>Drain</span><strong>${escapeHtml(cellGroup.control_state?.drain?.status || "idle")}</strong></div>
      <div class="inspector-row"><span>OAI observe</span><strong>${escapeHtml(observe?.runtime_state || "not captured")}</strong></div>
      <div class="inspector-row"><span>OAI project</span><strong>${escapeHtml(observe?.project_name || "n/a")}</strong></div>
      <div class="inspector-row"><span>Contract worker</span><strong>${escapeHtml(nativeContract?.worker_kind || "n/a")}</strong></div>
      <div class="inspector-row"><span>Contract transport</span><strong>${escapeHtml(nativeContract?.transport_worker || "n/a")}</strong></div>
      <div class="inspector-row"><span>Contract lane</span><strong>${escapeHtml(nativeContract?.execution_lane || "n/a")}</strong></div>
      <div class="inspector-row"><span>Topology</span><strong>${escapeHtml(data.ran.topology_source || "repo default")}</strong></div>
    </div>
  `;
}

function contractSummaryLabel(contract) {
  if (!contract) {
    return "No native contract data";
  }

  const pieces = [
    contract.backend_family,
    contract.worker_kind,
    contract.transport_worker || contract.execution_lane
  ].filter(Boolean);

  return pieces.length ? pieces.join(" / ") : "Native contract data present";
}

function contractFieldRows(contract) {
  if (!contract) {
    return [];
  }

  const health = contract.health || {};
  const signals = contract.signals || {};

  return [
    ["Backend family", contract.backend_family],
    ["Worker kind", contract.worker_kind],
    ["Transport worker", contract.transport_worker],
    ["Execution lane", contract.execution_lane],
    ["Dispatch mode", contract.dispatch_mode],
    ["Transport mode", contract.transport_mode],
    ["Policy mode", contract.policy_mode],
    ["Accepted profile", contract.accepted_profile],
    ["Fronthaul session", contract.fronthaul_session],
    ["Device session ref", contract.device_session_ref],
    ["Device session state", contract.device_session_state],
    ["Device generation", contract.device_generation],
    ["Device profile", contract.device_profile],
    ["Policy surface ref", contract.policy_surface_ref],
    ["Handshake ref", contract.handshake_ref],
    ["Handshake state", contract.handshake_state],
    ["Handshake attempts", contract.handshake_attempts],
    ["Last handshake", contract.last_handshake_at],
    ["Strict host probe", contract.strict_host_probe],
    ["Activation gate", contract.activation_gate],
    ["Handshake target", contract.handshake_target],
    ["Probe evidence ref", contract.probe_evidence_ref],
    ["Probe checked at", contract.probe_checked_at],
    [
      "Probe required resources",
      Array.isArray(contract.probe_required_resources)
        ? contract.probe_required_resources.join(", ")
        : contract.probe_required_resources
    ],
    ["Host probe ref", contract.host_probe_ref],
    ["Host probe status", contract.host_probe_status],
    ["Host probe mode", contract.host_probe_mode],
    [
      "Host probe failures",
      Array.isArray(contract.host_probe_failures)
        ? contract.host_probe_failures.join(", ")
        : contract.host_probe_failures
    ],
    [
      "Probe observations",
      contract.probe_observations && Object.keys(contract.probe_observations).length
        ? JSON.stringify(contract.probe_observations)
        : null
    ],
    ["Session epoch", contract.session_epoch],
    ["Session started", contract.session_started_at],
    ["Last submit", contract.last_submit_at],
    ["Last uplink", contract.last_uplink_at],
    ["Last resume", contract.last_resume_at],
    ["Drain state", contract.drain_state],
    ["Drain reason", contract.drain_reason],
    ["Queue depth", contract.queue_depth],
    ["Deadline misses", contract.deadline_miss_count],
    ["Timing window us", contract.timing_window_us],
    ["Timing budget us", contract.timing_budget_us],
    ["Worker state", contract.worker_state],
    ["Session state", contract.session_state],
    ["Transport state", contract.transport_state],
    ["Dispatch state", contract.dispatch_state],
    ["Health status", health.status || health.state || health.tone],
    [
      "Health checks",
      Array.isArray(health.checks) && health.checks.length
        ? health.checks
            .map((check) =>
              typeof check === "object"
                ? `${check.name || "check"}:${check.status || check.state || "unknown"}`
                : String(check)
            )
            .join(", ")
        : null
    ],
    [
      "Signals",
      Object.keys(signals).length
        ? Object.entries(signals)
            .map(([key, value]) => `${key}=${value}`)
            .join(", ")
        : null
    ],
    ["Source", contract.source_path || contract.source]
  ].filter(([, value]) => value !== null && value !== undefined && value !== "");
}

function renderPolicyPanel(data) {
  const bundles = data.release?.recent_bundles || [];
  const latestBundle = bundles[0];
  const retention = data.retention || {};
  const pruneCandidates = retention.prune_candidates || [];

  byId("policy-panel").innerHTML = `
    <div class="section-kicker">Policy</div>
    <h4>${escapeHtml(data.ran.validation.status || "unknown")} validation</h4>
    <div class="inspector-rows">
      <div class="inspector-row"><span>Profile</span><strong>${escapeHtml(data.ran.profile)}</strong></div>
      <div class="inspector-row"><span>Topology source</span><strong>${escapeHtml(data.ran.validation.topology_source || "repo default")}</strong></div>
      <div class="inspector-row"><span>Default backend</span><strong>${escapeHtml(data.ran.validation.default_backend || "n/a")}</strong></div>
      <div class="inspector-row"><span>Scheduler adapter</span><strong>${escapeHtml(data.ran.validation.scheduler_adapter || "n/a")}</strong></div>
      <div class="inspector-row"><span>Supported backends</span><strong>${escapeHtml((data.ran.validation.supported_backends || []).join(", "))}</strong></div>
      <div class="inspector-row"><span>Release readiness</span><strong>${escapeHtml(data.release?.readiness?.status || "unknown")}</strong></div>
      <div class="inspector-row"><span>Release unit</span><strong>${escapeHtml(data.release?.readiness?.release_unit || "n/a")}</strong></div>
      <div class="inspector-row"><span>Recent bundles</span><strong>${escapeHtml(bundles.length)}</strong></div>
      <div class="inspector-row"><span>Latest bundle</span><strong>${escapeHtml(latestBundle?.bundle_id || "none")}</strong></div>
      <div class="inspector-row"><span>Prune candidates</span><strong>${escapeHtml(retention.summary?.prune_count || 0)}</strong></div>
      <div class="inspector-row"><span>Protected refs</span><strong>${escapeHtml(retention.summary?.protected_count || 0)}</strong></div>
    </div>
    <div class="lane-list">
      ${latestBundle
        ? `
            <div class="lane-note">${escapeHtml(latestBundle.manifest_path || "n/a")}</div>
            <div class="lane-note">${escapeHtml(latestBundle.tarball_path || "n/a")}</div>
          `
        : `<div class="lane-note">No bootstrap bundles recorded yet.</div>`}
      ${pruneCandidates.length
        ? pruneCandidates
            .slice(0, 3)
            .map((item) => `<div class="lane-note">prune ${escapeHtml(item.category)} :: ${escapeHtml(item.path)}</div>`)
            .join("")
        : `<div class="lane-note">Retention planner has no pending prune candidates.</div>`}
    </div>
  `;
}

function renderNativeContractPanel(focusedRun) {
  const target = byId("contract-panel");
  const contract = focusedRun?.native_contract || null;

  if (!contract) {
    target.innerHTML = `<div class="empty">No native contract metadata attached to the focused run.</div>`;
    return;
  }

  const rows = contractFieldRows(contract);
  const health = contract.health || {};
  const timingTags = [
    contract.session_epoch ? `epoch ${contract.session_epoch}` : null,
    contract.queue_depth !== undefined && contract.queue_depth !== null ? `queue ${contract.queue_depth}` : null,
    contract.drain_state || null
  ].filter(Boolean);

  target.innerHTML = `
    <div class="section-kicker">Native Contract</div>
    <h4>${escapeHtml(focusedRun.id)}</h4>
    <div class="inspector-meta">${escapeHtml(contractSummaryLabel(contract))}</div>
    <div class="focus-tags">
      ${[contract.backend_family, contract.worker_kind, contract.transport_worker, contract.execution_lane]
        .filter(Boolean)
        .map((value) => `<span class="runtime-tag">${escapeHtml(value)}</span>`)
        .join("")}
      ${timingTags.map((value) => `<span class="runtime-tag">${escapeHtml(value)}</span>`).join("")}
      ${health.status ? `<span class="runtime-tag">${escapeHtml(health.status)}</span>` : ""}
    </div>
    <div class="inspector-rows">
      ${rows
        .map(
          ([label, value]) => `
            <div class="inspector-row"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>
          `
        )
        .join("")}
    </div>
  `;
}

function protocolStatusPill(status) {
  return `<span class="status-pill ${escapeHtml(status || "unknown")}">${escapeHtml(status || "unknown")}</span>`;
}

function formatSourceParts(parts) {
  return parts.filter((part) => part !== null && part !== undefined && part !== "").join(" :: ");
}

function renderProtocolField(field) {
  return `
    <div class="protocol-detail">
      <div class="inspector-row">
        <span>${escapeHtml(field.label || field.id)}</span>
        <strong>${escapeHtml(field.value ?? "n/a")}</strong>
      </div>
      <div class="lane-note">${escapeHtml(field.meaning || "No meaning documented.")}</div>
      <div class="lane-note">Source: ${escapeHtml(formatSourceParts([field.source_kind, field.source_field, field.source_ref]) || "n/a")}</div>
    </div>
  `;
}

function renderProtocolCounter(counter) {
  const source = formatSourceParts([
    counter.source_kind,
    counter.source_pattern ? `token ${counter.source_pattern}` : counter.source_field,
    counter.source_tail_lines ? `${counter.source_tail_lines} tail lines` : null,
    counter.source_ref
  ]);

  return `
    <div class="protocol-detail">
      <div class="inspector-row">
        <span>${escapeHtml(counter.label || counter.id)}</span>
        <strong>${escapeHtml(counter.count ?? 0)}</strong>
      </div>
      <div class="lane-note">${escapeHtml(counter.meaning || "No meaning documented.")}</div>
      <div class="lane-note">Source: ${escapeHtml(source || "n/a")}</div>
    </div>
  `;
}

function renderProtocolEvidenceRow(row, note) {
  const notes = [
    note,
    row.evidence_ref ? `Evidence: ${row.evidence_ref}` : null,
    row.standards_subset_ref ? `Subset: ${row.standards_subset_ref}` : null,
    row.procedure_matrix_ref ? `Matrix: ${row.procedure_matrix_ref}` : null
  ]
    .filter(Boolean)
    .map((text) => `<div class="lane-note">${escapeHtml(text)}</div>`)
    .join("");

  return `
    <div class="protocol-detail">
      <div class="runtime-top">
        <div class="inspector-title">${escapeHtml(row.label || row.id)}</div>
        ${protocolStatusPill(row.status)}
      </div>
      ${notes}
    </div>
  `;
}

function renderProtocolRowSection(title, rows, noteBuilder) {
  if (!rows?.length) {
    return "";
  }

  return `
    <div class="section-kicker">${escapeHtml(title)}</div>
    <div class="protocol-grid">
      ${rows.map((row) => renderProtocolEvidenceRow(row, noteBuilder(row))).join("")}
    </div>
  `;
}

function renderSimulationProtocolCard(panel) {
  return `
    <div class="protocol-card simulation">
      <div class="runtime-top">
        <div>
          <div class="inspector-title">${escapeHtml(panel.label || panel.role || "service")}</div>
          <div class="inspector-meta">${escapeHtml(formatSourceParts([panel.service_name, panel.container_name]) || "observe artifact")}</div>
        </div>
        ${protocolStatusPill(panel.status)}
      </div>
      <div class="focus-tags">
        <span class="runtime-tag">${escapeHtml(panel.role || "service")}</span>
        <span class="runtime-tag">${escapeHtml(`${panel.counters?.length || 0} documented counters`)}</span>
      </div>
      <div class="section-kicker">Documented Fields</div>
      <div class="protocol-grid">
        ${(panel.fields || []).map(renderProtocolField).join("")}
      </div>
      <div class="section-kicker">Documented Counters</div>
      <div class="protocol-grid">
        ${(panel.counters || []).length
          ? panel.counters.map(renderProtocolCounter).join("")
          : '<div class="lane-note">No documented counters were captured for this role in the current observe artifact.</div>'}
      </div>
    </div>
  `;
}

function renderSimulationProtocolSection(observe) {
  if (!observe?.protocol_panels?.length) {
    return `
      <div class="protocol-section">
        <div class="inspector-row"><span>Repo-local simulation lane</span><strong>not captured</strong></div>
        <div class="lane-note">No repo-local OAI observe artifact is available for the focused mission.</div>
      </div>
    `;
  }

  return `
    <div class="protocol-section">
      <div class="inspector-row">
        <span>Repo-local simulation lane</span>
        ${protocolStatusPill(observe.runtime_state)}
      </div>
      <div class="lane-note">${escapeHtml(observe.proof_note || "Repo-local simulation proof is available.")}</div>
      <div class="focus-tags">
        <span class="runtime-tag">${escapeHtml(observe.lane_id || "oai_split_rfsim_repo_local_v1")}</span>
        <span class="runtime-tag">${escapeHtml(`${observe.running_service_count}/${observe.service_count} running`)}</span>
        <span class="runtime-tag">${escapeHtml(`${observe.healthy_service_count} healthy`)}</span>
        <span class="runtime-tag">${escapeHtml(observe.updated_at || "n/a")}</span>
      </div>
      <div class="lane-note">Source: ${escapeHtml(observe.path || "n/a")}</div>
      <div class="protocol-cards">
        ${observe.protocol_panels.map(renderSimulationProtocolCard).join("")}
      </div>
    </div>
  `;
}

function renderBoundedProtocolSection(protocolState) {
  if (!protocolState) {
    return `
      <div class="protocol-section">
        <div class="inspector-row"><span>Bounded standards lane</span><strong>select a protocol run</strong></div>
        <div class="lane-note">Select an observe or verify run with declared protocol evidence to inspect NGAP, F1, E1AP, and attach/session outcomes.</div>
      </div>
    `;
  }

  return `
    <div class="protocol-section">
      <div class="inspector-row">
        <span>Bounded standards lane</span>
        ${protocolStatusPill(protocolState.gate_class || protocolState.evidence_tier || "evidence")}
      </div>
      <div class="lane-note">${escapeHtml(protocolState.proof_note || "Bounded standards proof is attached to the focused run.")}</div>
      <div class="lane-note">${escapeHtml(protocolState.summary || "No summary attached.")}</div>
      <div class="focus-tags">
        ${[protocolState.evidence_tier, protocolState.core_profile, protocolState.target_profile, protocolState.conformance_profile]
          .filter(Boolean)
          .map((value) => `<span class="runtime-tag">${escapeHtml(value)}</span>`)
          .join("")}
        ${protocolState.ngap_last_observed ? `<span class="runtime-tag">${escapeHtml(`last NGAP ${protocolState.ngap_last_observed}`)}</span>` : ""}
      </div>
      <div class="lane-note">Source: ${escapeHtml(protocolState.source_ref || "n/a")}</div>
      ${protocolState.baseline_ref ? `<div class="lane-note">Baseline: ${escapeHtml(protocolState.baseline_ref)}</div>` : ""}
      ${renderProtocolRowSection("Interface State", protocolState.interface_rows, (row) => row.reason)}
      ${renderProtocolRowSection("Plane State", protocolState.plane_rows, (row) => row.reason)}
      ${renderProtocolRowSection("NGAP Procedure Trace", protocolState.procedure_rows, (row) => row.detail)}
      ${renderProtocolRowSection("Outcome State", protocolState.outcome_rows, (row) => row.reason)}
    </div>
  `;
}

function renderProtocolStatePanel(cellGroup, focusedRun) {
  const target = byId("protocol-panel");
  const observe = currentOaiObservation(cellGroup);
  const protocolState = focusedRun?.protocol_state || null;

  if (!observe?.protocol_panels?.length && !protocolState) {
    target.innerHTML = `<div class="empty">No DU/CU protocol-state evidence is available for the focused mission or run.</div>`;
    return;
  }

  target.innerHTML = `
    <div class="section-kicker">DU/CU Protocol State</div>
    <h4>${escapeHtml(cellGroup?.id || observe?.project_name || focusedRun?.id || "protocol state")}</h4>
    <div class="inspector-meta">Simulation proof and bounded-standards proof stay visually distinct in the focused context.</div>
    ${renderSimulationProtocolSection(observe)}
    ${renderBoundedProtocolSection(protocolState)}
  `;
}

function renderInspectorKeyValue(label, value) {
  return `
    <div class="inspector-row">
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value ?? "n/a")}</strong>
    </div>
  `;
}

function renderArtifactRefCard(ref) {
  return `
    <div class="protocol-detail">
      <div class="runtime-top">
        <div class="inspector-title">${escapeHtml(ref.label || ref.id || "artifact ref")}</div>
        <span class="runtime-tag">${escapeHtml(ref.kind || "ref")}</span>
      </div>
      <div class="lane-note">${escapeHtml(ref.ref || "n/a")}</div>
    </div>
  `;
}

function renderArtifactRefBlock(title, refs, emptyMessage) {
  return `
    <div class="section-kicker">${escapeHtml(title)}</div>
    ${refs?.length
      ? `<div class="protocol-grid">${refs.map(renderArtifactRefCard).join("")}</div>`
      : `<div class="lane-note">${escapeHtml(emptyMessage)}</div>`}
  `;
}

function renderProvenanceCard(entry) {
  const tags = [
    entry.proof_kind,
    entry.evidence_tier,
    entry.conformance_profile,
    entry.target_profile,
    entry.core_profile,
    entry.reference_count ? `${entry.reference_count} refs` : null
  ].filter(Boolean);

  return `
    <div class="protocol-detail">
      <div class="runtime-top">
        <div class="inspector-title">${escapeHtml(entry.lane || "provenance")}</div>
        <span class="runtime-tag">${escapeHtml(entry.proof_kind || "evidence")}</span>
      </div>
      ${entry.note ? `<div class="lane-note">${escapeHtml(entry.note)}</div>` : ""}
      ${entry.baseline_ref ? `<div class="lane-note">Baseline: ${escapeHtml(entry.baseline_ref)}</div>` : ""}
      ${tags.length
        ? `<div class="focus-tags">${tags.map((tag) => `<span class="runtime-tag">${escapeHtml(tag)}</span>`).join("")}</div>`
        : ""}
    </div>
  `;
}

function renderArtifactBundleSection(bundle) {
  if (!bundle) {
    return "";
  }

  const manifest = bundle.manifest || {};
  const manifestRows = [
    ["Bundle ref", manifest.ref],
    ["Captured at", manifest.captured_at],
    ["Scope", manifest.scope],
    ["Cell group", manifest.cell_group],
    ["Change", manifest.change_id],
    ["Incident", manifest.incident_id],
    ["Artifact root", manifest.artifact_root]
  ].filter(([, value]) => value !== null && value !== undefined && value !== "");

  return `
    <div class="protocol-section">
      <div class="inspector-row">
        <span>Artifact bundle</span>
        <strong>${escapeHtml(manifest.ref || manifest.change_id || "indexed")}</strong>
      </div>
      ${bundle.summary ? `<div class="lane-note">${escapeHtml(bundle.summary)}</div>` : ""}
      <div class="protocol-grid">
        <div class="protocol-card">
          <div class="section-kicker">Manifest</div>
          ${manifestRows.length
            ? `<div class="inspector-rows">${manifestRows.map(([label, value]) => renderInspectorKeyValue(label, value)).join("")}</div>`
            : `<div class="lane-note">No manifest rows were indexed for this bundle.</div>`}
          <div class="lane-note">Source: ${escapeHtml(bundle.source_ref || "n/a")}</div>
        </div>
        ${bundle.provenance?.length
          ? `
            <div class="protocol-card">
              <div class="section-kicker">Provenance</div>
              <div class="protocol-grid">
                ${bundle.provenance.map(renderProvenanceCard).join("")}
              </div>
            </div>
          `
          : ""}
      </div>
      ${renderArtifactRefBlock("Workflow refs", bundle.workflow_refs, "No workflow refs were indexed for this bundle.")}
      ${renderArtifactRefBlock("Runtime refs", bundle.runtime_refs, "No runtime refs were indexed for this bundle.")}
      ${renderArtifactRefBlock("Review refs", bundle.review_refs, "No review refs were indexed for this bundle.")}
      ${renderArtifactRefBlock(
        "Declared lane evidence",
        bundle.declared_lane_refs,
        "No declared lane evidence refs were indexed for this bundle."
      )}
    </div>
  `;
}

function renderRollbackCheckCard(check) {
  return `
    <div class="protocol-detail">
      <div class="runtime-top">
        <div class="inspector-title">${escapeHtml(check.name || "review check")}</div>
        ${protocolStatusPill(check.status || "unknown")}
      </div>
      <div class="lane-note">${escapeHtml(check.detail || "No detail available.")}</div>
    </div>
  `;
}

function renderRollbackReplaySection(drilldown) {
  if (!drilldown) {
    return "";
  }

  const contextRows = [
    ["Status", drilldown.status || (drilldown.rollback_available ? "available" : "unknown")],
    ["Rollback target", drilldown.rollback_target],
    ["Restored from", drilldown.restored_from],
    ["Comparison scope", drilldown.comparison_scope],
    ["Rollback available", drilldown.rollback_available ? "yes" : "no"]
  ].filter(([, value]) => value !== null && value !== undefined && value !== "");

  const tags = [
    drilldown.comparison_scope ? `scope ${drilldown.comparison_scope}` : null,
    ...(drilldown.provenance || []).map((entry) => entry.lane).filter(Boolean)
  ].filter(Boolean);

  return `
    <div class="protocol-section">
      <div class="inspector-row">
        <span>Rollback and replay</span>
        ${protocolStatusPill(drilldown.status || (drilldown.rollback_available ? "ok" : "unknown"))}
      </div>
      ${drilldown.summary ? `<div class="lane-note">${escapeHtml(drilldown.summary)}</div>` : ""}
      ${drilldown.reason ? `<div class="lane-note">${escapeHtml(drilldown.reason)}</div>` : ""}
      ${tags.length
        ? `<div class="focus-tags">${tags.map((tag) => `<span class="runtime-tag">${escapeHtml(tag)}</span>`).join("")}</div>`
        : ""}
      <div class="protocol-grid">
        <div class="protocol-card">
          <div class="section-kicker">Recovery context</div>
          <div class="inspector-rows">
            ${contextRows.map(([label, value]) => renderInspectorKeyValue(label, value)).join("")}
          </div>
          <div class="lane-note">Source: ${escapeHtml(drilldown.source_ref || "n/a")}</div>
        </div>
        ${drilldown.review_checks?.length
          ? `
            <div class="protocol-card">
              <div class="section-kicker">Review checks</div>
              <div class="protocol-grid">
                ${drilldown.review_checks.map(renderRollbackCheckCard).join("")}
              </div>
            </div>
          `
          : ""}
      </div>
      ${renderArtifactRefBlock("Replay inputs", drilldown.replay_refs, "No replay inputs were indexed for this run.")}
      ${renderArtifactRefBlock("Rollback evidence", drilldown.rollback_refs, "No rollback evidence refs were indexed for this run.")}
      ${drilldown.suggested_next?.length
        ? `
          <div class="section-kicker">Suggested next</div>
          <div class="lane-list">
            ${drilldown.suggested_next
              .map((step) => `<div class="lane-note">${escapeHtml(step)}</div>`)
              .join("")}
          </div>
        `
        : ""}
    </div>
  `;
}

function renderRawRefSection(refs) {
  return `
    <div class="protocol-section">
      <div class="section-kicker">Direct refs</div>
      ${refs.length
        ? `
          <div class="lane-list">
            ${refs
              .slice(0, 8)
              .map(
                (ref) => `
                  <div class="lane-note">${escapeHtml(ref)}</div>
                `
              )
              .join("")}
          </div>
        `
        : `<div class="lane-note">No artifact refs attached.</div>`}
    </div>
  `;
}

function renderRunPanel(focusedRun) {
  const target = byId("run-panel");

  if (!focusedRun) {
    target.innerHTML = `<div class="empty">No run contract selected.</div>`;
    return;
  }

  const refs = [
    focusedRun.path,
    focusedRun.approval_ref,
    focusedRun.rollback_plan_ref,
    focusedRun.source_plan,
    ...(focusedRun.artifacts || [])
  ].filter(Boolean);
  const artifactBundle = focusedRun.artifact_bundle || null;
  const rollbackReplay = focusedRun.rollback_replay || null;

  target.innerHTML = `
    <div class="section-kicker">Run Contract</div>
    <h4>${escapeHtml(focusedRun.id)}</h4>
    <div class="inspector-meta">${escapeHtml(focusedRun.summary || `${focusedRun.command || "artifact"} / ${focusedRun.status || "unknown"}`)}</div>
    <div class="inspector-rows">
      <div class="inspector-row"><span>Command</span><strong>${escapeHtml(focusedRun.command || focusedRun.phase || "unknown")}</strong></div>
      <div class="inspector-row"><span>Status</span><strong>${escapeHtml(focusedRun.status || "unknown")}</strong></div>
      <div class="inspector-row"><span>Phase</span><strong>${escapeHtml(focusedRun.phase || "unknown")}</strong></div>
      <div class="inspector-row"><span>Target backend</span><strong>${escapeHtml(focusedRun.target_backend || "n/a")}</strong></div>
      <div class="inspector-row"><span>Native contract</span><strong>${escapeHtml(contractSummaryLabel(focusedRun.native_contract || null))}</strong></div>
      <div class="inspector-row"><span>Rollback from</span><strong>${escapeHtml(focusedRun.restored_from || "n/a")}</strong></div>
      <div class="inspector-row"><span>Next</span><strong>${escapeHtml((focusedRun.next || []).join(" -> ") || "none")}</strong></div>
    </div>
    ${renderArtifactBundleSection(artifactBundle)}
    ${renderRollbackReplaySection(rollbackReplay)}
    ${renderRawRefSection(refs)}
  `;
}

function renderEvidencePanel(evidence) {
  const target = byId("evidence-panel");

  if (!evidence) {
    target.innerHTML = `<div class="empty">No evidence attached.</div>`;
    return;
  }

  target.innerHTML = `
    <div class="section-kicker">Evidence</div>
    <h4>${escapeHtml(evidence.name)}</h4>
    <div class="inspector-meta">${escapeHtml(evidence.updated_at)}</div>
    <ul class="evidence-lines">
      ${(evidence.excerpt || []).map((line) => `<li>${escapeHtml(line)}</li>`).join("")}
    </ul>
  `;
}

function renderLanePanel(data, focusedRun) {
  byId("lane-panel").innerHTML = `
    <div class="section-kicker">Orchestration Lanes</div>
    <h4>${escapeHtml(focusedRun?.id || "current workspace")}</h4>
    <div class="lane-list">
      ${(data.agents.lanes || [])
        .map(
          (lane) => `
            <div>
              <div class="inspector-row"><strong>${escapeHtml(lane.name)}</strong></div>
              <div class="lane-note">${escapeHtml(lane.summary)}</div>
            </div>
          `
        )
        .join("")}
    </div>
  `;
}

function deployValue(key) {
  return state.deployForm?.[key] ?? "";
}

function buildQuickInstallCommand(applyMode) {
  const parts = ["bin/ran-install"];
  const bundle = state.lastDeploy?.result?.bundle_tarball || deployValue("bundle_tarball");
  const deployProfile = deployValue("deploy_profile");
  const targetHost = deployValue("target_host");
  const sshUser = deployValue("ssh_user");
  const sshPort = deployValue("ssh_port");

  if (bundle) {
    parts.push("--bundle", bundle);
  }

  if (deployProfile) {
    parts.push("--deploy-profile", deployProfile);
  }

  if (targetHost) {
    parts.push("--target-host", targetHost);
  }

  if (sshUser) {
    parts.push("--ssh-user", sshUser);
  }

  if (sshPort) {
    parts.push("--ssh-port", sshPort);
  }

  if (applyMode) {
    if (!targetHost) {
      return "Set target_host first to build an executable install command.";
    }

    parts.push("--apply", "--remote-precheck");
  }

  return parts.map(shellQuote).join(" ");
}

function renderDeployStudio(data) {
  const deploy = data.deploy || {};
  const debug = data.debug || {};
  const defaults = deploy.defaults || {};
  const recentRemoteRuns = deploy.recent_remote_runs || [];
  const recentInstallRuns = deploy.recent_install_runs || [];
  const latestDebugIncident = deploy.latest_debug_incident || debug.latest_failure || null;
  const recentDebugFailures = deploy.recent_debug_failures || debug.recent_failures || [];
  const profileCatalog = deploy.profile_catalog || [];
  const activeProfile = profileCatalog.find((profile) => profile.name === deployValue("deploy_profile"));
  const activeProfileSteps = activeProfile?.operator_steps || [];
  const activeProfileTargets = activeProfile?.recommended_for || [];
  const outputPanel = byId("deploy-output-panel");
  const formPanel = byId("deploy-form-panel");

  byId("deploy-status-chip").textContent = state.lastDeploy?.result?.preflight?.status
    || state.lastDeploy?.result?.status
    || deploy.status
    || "preview";

  formPanel.innerHTML = `
    <div class="section-kicker">Deploy Inputs</div>
    <h4>Repo-local staging first</h4>
    <div class="deploy-meta">${escapeHtml(deploy.summary || "Generate target-host files into a safe preview root, then move the bundle to the live server.")}</div>
    <label class="deploy-field deploy-field-wide">
      <span>Deploy profile</span>
      <select data-deploy-field="deploy_profile">
        ${profileCatalog
          .map(
            (profile) => `
              <option value="${escapeHtml(profile.name)}" ${profile.name === deployValue("deploy_profile") ? "selected" : ""}>
                ${escapeHtml(profile.title)} :: ${escapeHtml(profile.name)}
              </option>
            `
          )
          .join("")}
      </select>
    </label>
    <div class="deploy-helpers">
      <div class="lane-note">selected profile :: ${escapeHtml(activeProfile?.title || deployValue("deploy_profile") || "n/a")}</div>
      <div class="lane-note">${escapeHtml(activeProfile?.description || "No deploy profile description available.")}</div>
      <div class="lane-note">profile overlays :: ${escapeHtml((activeProfile?.overlays || []).join(", ") || "n/a")}</div>
    </div>
    <div class="deploy-profile-card">
      <div class="focus-tags">
        <span class="runtime-tag">${escapeHtml(activeProfile?.stability_tier || "unknown")}</span>
        <span class="runtime-tag">${escapeHtml(activeProfile?.exposure || "unknown")}</span>
      </div>
      <div class="section-kicker">Recommended For</div>
      <div class="lane-list">
        ${renderLaneNotes(activeProfileTargets, "No recommended target environment recorded.")}
      </div>
      <div class="section-kicker">Profile Runbook</div>
      <div class="lane-list">
        ${renderLaneNotes(activeProfileSteps, "No profile runbook recorded.")}
      </div>
    </div>
    <div class="deploy-form-grid">
      ${DEPLOY_TEXT_FIELDS.map(
        ([key, label]) => `
          <label class="deploy-field">
            <span>${escapeHtml(label)}</span>
            <input data-deploy-field="${escapeHtml(key)}" type="text" value="${escapeHtml(deployValue(key))}">
          </label>
        `
      ).join("")}
    </div>
    <div class="deploy-toggle-row">
      ${DEPLOY_BOOL_FIELDS.map(
        ([key, label]) => `
          <label class="deploy-toggle">
            <input data-deploy-field="${escapeHtml(key)}" type="checkbox" ${deployValue(key) ? "checked" : ""}>
            <span>${escapeHtml(label)}</span>
          </label>
        `
      ).join("")}
    </div>
      <div class="deploy-helpers">
      <div class="lane-note">safe preview root :: ${escapeHtml(deploy.safe_preview_root || defaults.safe_preview_root || "n/a")}</div>
      <div class="lane-note">recommended actions :: ${escapeHtml((deploy.recommended_actions || []).join(", ") || "preview, preflight")}</div>
      <div class="lane-note">recent remote runs :: ${escapeHtml(deploy.recent_remote_run_count || 0)}</div>
      <div class="lane-note">recent install runs :: ${escapeHtml(deploy.recent_install_run_count || 0)}</div>
    </div>
    <div class="deploy-actions">
      <button class="action-button primary" data-deploy-command="preview" type="button">Generate Preview</button>
      <button class="action-button" data-deploy-command="preflight" type="button">Run Preflight</button>
      <button class="action-button" data-deploy-reset="true" type="button">Reset Defaults</button>
    </div>
  `;

  if (!state.lastDeploy) {
    outputPanel.innerHTML = `
      <div class="section-kicker">Deploy Output</div>
      <h4>Waiting for preview</h4>
      <div class="deploy-meta">Generate a preview to materialize topology, request, env, and readiness files into repo-local staging.</div>
      <div class="deploy-profile-card">
        <div class="section-kicker">Profile posture</div>
        <h4>${escapeHtml(activeProfile?.title || deployValue("deploy_profile") || "unselected profile")}</h4>
        <div class="deploy-meta">${escapeHtml(activeProfile?.description || "Select a profile to load the recommended operator posture.")}</div>
        <div class="focus-tags">
          <span class="runtime-tag">${escapeHtml(activeProfile?.stability_tier || "unknown")}</span>
          <span class="runtime-tag">${escapeHtml(activeProfile?.exposure || "unknown")}</span>
        </div>
        <div class="lane-list">
          ${renderLaneNotes(activeProfileSteps, "Run Generate Preview to materialize a readiness file and step-by-step rollout advice.")}
        </div>
      </div>
      <div class="lane-list">
        <div class="lane-note">${escapeHtml(defaults.bundle_tarball || "No bundle discovered yet.")}</div>
        ${recentRemoteRuns.length
          ? recentRemoteRuns
              .slice(0, 3)
              .map(
                (run) => `<div class="lane-note">[${escapeHtml(run.status || "unknown")}] ${escapeHtml(run.host)} :: ${escapeHtml(run.command || run.label)}</div>`
              )
              .join("")
          : '<div class="lane-note">No remote run transcripts captured yet.</div>'}
      </div>
      <div class="deploy-preview-stack">
        ${renderDeployCommandCard(
          "Easy install preview",
          activeProfile?.title || "preview",
          buildQuickInstallCommand(false),
          "deploy-copy-install-preview"
        )}
        ${renderDeployCommandCard(
          "Easy install apply",
          deployValue("target_host") ? "ready" : "needs target_host",
          buildQuickInstallCommand(true),
          "deploy-copy-install-apply"
        )}
        ${renderDeployCommandCard(
          "Latest debug CLI",
          latestDebugIncident ? (latestDebugIncident.status || latestDebugIncident.kind || "ready") : "no failures",
          "bin/ran-debug-latest --failures-only",
          "deploy-copy-debug-latest"
        )}
        <section class="deploy-preview-card">
          <div class="inspector-row deploy-row"><span>Install Debug Index</span><strong>${escapeHtml(recentInstallRuns.length)}</strong></div>
          <pre>${escapeHtml(
            recentInstallRuns.length
              ? recentInstallRuns
                  .slice(0, 5)
                  .map((run) =>
                    [
                      `[${run.kind || "install"}] ${run.status || "unknown"}`,
                      run.host ? `host=${run.host}` : null,
                      run.deploy_profile ? `profile=${run.deploy_profile}` : null,
                      run.readiness_status ? `readiness=${run.readiness_status}` : null,
                      run.summary_path || run.guide_path || run.path
                    ]
                      .filter(Boolean)
                      .join("\n")
                  )
                  .join("\n\n")
              : "No install debug runs recorded yet."
          )}</pre>
        </section>
        <section class="deploy-preview-card">
          <div class="inspector-row deploy-row"><span>Latest Debug Incident</span><strong>${escapeHtml(latestDebugIncident?.status || "none")}</strong></div>
          <pre>${escapeHtml(debugIncidentSummary(latestDebugIncident))}</pre>
        </section>
      </div>
    `;
    return;
  }

  const result = state.lastDeploy.result || {};
  const previews = result.previews || {};
  const nextSteps = result.next_steps || [];
  const handoff = result.handoff || {};
  const remoteRanctlCommands = handoff.remote_ranctl_commands || [];
  const fetchCommands = handoff.fetch_commands || [];
  const readiness = result.readiness || {};
  const readinessChecklist = readiness.checklist || [];
  const blockers = readiness.blockers || [];
  const warnings = readiness.warnings || [];
  const remoteRunSummary = recentRemoteRuns.length
    ? recentRemoteRuns
        .slice(0, 4)
        .map(
          (run) => [
            `[${run.status || "unknown"}] ${run.host} :: ${run.command || run.label}`,
            run.change_id ? `change=${run.change_id}` : null,
            run.cell_group ? `cell_group=${run.cell_group}` : null,
            run.fetch_status ? `fetch=${run.fetch_status}` : null,
            run.fetch_archive_path || run.result_path || run.plan_path || run.path
          ]
            .filter(Boolean)
            .join("\n")
        )
        .join("\n\n")
    : "No remote run transcripts captured yet.";
  const previewCards = [
    ["Topology", previews.topology],
    ["Request", previews.request],
    ["Dashboard env", previews.dashboard_env],
    ["Preflight env", previews.preflight_env],
    ["Deploy profile", previews.profile_manifest],
    ["Effective config", previews.effective_config],
    ["Deploy readiness", previews.readiness]
  ];

  outputPanel.innerHTML = `
    <div class="section-kicker">Deploy Output</div>
    <h4>${escapeHtml(state.lastDeploy.mode || "preview")} result</h4>
    <div class="deploy-meta">${escapeHtml(state.lastDeploy.message || "Wizard response captured.")}</div>
    <div class="inspector-rows">
      <div class="inspector-row deploy-row"><span>Status</span><strong>${escapeHtml(result.status || "unknown")}</strong></div>
      <div class="inspector-row deploy-row"><span>Current root</span><strong>${escapeHtml(result.current_root || "n/a")}</strong></div>
      <div class="inspector-row deploy-row"><span>Config root</span><strong>${escapeHtml(result.etc_root || "n/a")}</strong></div>
      <div class="inspector-row deploy-row"><span>Bundle</span><strong>${escapeHtml(result.bundle_tarball || "n/a")}</strong></div>
      <div class="inspector-row deploy-row"><span>Preflight</span><strong>${escapeHtml(result.preflight?.status || "skipped")}</strong></div>
      <div class="inspector-row deploy-row"><span>Remote host</span><strong>${escapeHtml(handoff.ssh_target || "not set")}</strong></div>
    </div>
    <section class="deploy-profile-card">
      <div class="section-kicker">Deploy Readiness</div>
      <h4>${escapeHtml(readiness.status || "unknown")}</h4>
      <div class="deploy-meta">${escapeHtml(readiness.summary || "No readiness summary returned.")}</div>
      <div class="focus-tags">
        <span class="runtime-tag">${escapeHtml(`${readiness.score ?? 0}/100`)}</span>
        <span class="runtime-tag">${escapeHtml(readiness.recommendation || "n/a")}</span>
        <span class="runtime-tag">${escapeHtml(readiness.profile?.name || deployValue("deploy_profile") || "n/a")}</span>
        <span class="runtime-tag">${escapeHtml(readiness.posture?.stability_tier || activeProfile?.stability_tier || "n/a")}</span>
      </div>
      <div class="inspector-rows">
        <div class="inspector-row deploy-row"><span>Strict probe</span><strong>${escapeHtml(String(readiness.posture?.strict_host_probe ?? deployValue("strict_host_probe")))}</strong></div>
        <div class="inspector-row deploy-row"><span>Pull images</span><strong>${escapeHtml(String(readiness.posture?.pull_images ?? deployValue("pull_images")))}</strong></div>
        <div class="inspector-row deploy-row"><span>Dashboard bind</span><strong>${escapeHtml(readiness.posture?.dashboard_host || deployValue("dashboard_host") || "n/a")}</strong></div>
        <div class="inspector-row deploy-row"><span>Evidence capture</span><strong>${escapeHtml(readiness.posture?.evidence_capture || "n/a")}</strong></div>
      </div>
      ${renderDeployChecklist(readinessChecklist)}
      <div class="section-kicker">Blockers</div>
      <div class="lane-list">${renderLaneNotes(blockers.map((item) => `${item.label} :: ${item.detail}`), "No deploy blockers recorded.")}</div>
      <div class="section-kicker">Warnings</div>
      <div class="lane-list">${renderLaneNotes(warnings.map((item) => `${item.label} :: ${item.detail}`), "No deploy warnings recorded.")}</div>
    </section>
    <div class="deploy-preview-stack">
      ${previewCards
        .map(([label, preview]) => `
          <section class="deploy-preview-card">
            <div class="inspector-row deploy-row"><span>${escapeHtml(label)}</span><strong>${escapeHtml(preview?.path || "n/a")}</strong></div>
            <pre>${escapeHtml(preview?.content || preview?.error || "not generated")}</pre>
          </section>
        `)
        .join("")}
      <section class="deploy-preview-card">
        <div class="inspector-row deploy-row"><span>Preflight output</span><strong>${escapeHtml(result.preflight?.status || "skipped")}</strong></div>
        <pre>${escapeHtml(result.preflight?.output || "Preflight was not executed in this run.")}</pre>
      </section>
      ${renderDeployCommandCard(
        "Easy install preview",
        activeProfile?.title || "preview",
        buildQuickInstallCommand(false),
        "deploy-copy-install-preview"
      )}
      ${renderDeployCommandCard(
        "Easy install apply",
        handoff.enabled ? "ready" : "needs target_host",
        buildQuickInstallCommand(true),
        "deploy-copy-install-apply"
      )}
      ${renderDeployCommandCard(
        "Latest debug CLI",
        latestDebugIncident ? (latestDebugIncident.status || latestDebugIncident.kind || "ready") : "no failures",
        "bin/ran-debug-latest --failures-only",
        "deploy-copy-debug-latest"
      )}
      ${renderDeployCommandCard(
        "Remote handoff",
        handoff.enabled ? handoff.ssh_target : "configure target_host to enable",
        handoff.commands?.length
          ? handoff.commands.join("\n")
          : "Set target_host, ssh_user, and remote paths to generate ssh/scp install commands.",
        "deploy-copy-handoff"
      )}
      ${renderDeployCommandCard(
        "Remote ranctl",
        handoff.enabled ? "ready" : "disabled",
        remoteRanctlCommands.length
          ? remoteRanctlCommands.join("\n")
          : "Remote ranctl helper commands will appear once target_host is configured.",
        "deploy-copy-ranctl"
      )}
      ${renderDeployCommandCard(
        "Evidence fetchback",
        handoff.enabled ? "ready" : "disabled",
        fetchCommands.length
          ? fetchCommands.join("\n")
          : "Remote evidence fetch commands will appear once target_host is configured.",
        "deploy-copy-fetch"
      )}
      <section class="deploy-preview-card">
        <div class="inspector-row deploy-row"><span>Install Debug Index</span><strong>${escapeHtml(recentInstallRuns.length)}</strong></div>
        <pre>${escapeHtml(
          recentInstallRuns.length
            ? recentInstallRuns
                .slice(0, 5)
                .map((run) =>
                  [
                    `[${run.kind || "install"}] ${run.status || "unknown"}`,
                    run.host ? `host=${run.host}` : null,
                    run.deploy_profile ? `profile=${run.deploy_profile}` : null,
                    run.readiness_status ? `readiness=${run.readiness_status}` : null,
                    run.summary_path || run.guide_path || run.path
                  ]
                    .filter(Boolean)
                    .join("\n")
                )
                .join("\n\n")
            : "No install debug runs recorded yet."
        )}</pre>
      </section>
      <section class="deploy-preview-card">
        <div class="inspector-row deploy-row"><span>Remote Run Index</span><strong>${escapeHtml(recentRemoteRuns.length)}</strong></div>
        <pre>${escapeHtml(remoteRunSummary)}</pre>
      </section>
      <section class="deploy-preview-card">
        <div class="inspector-row deploy-row"><span>Latest Debug Incident</span><strong>${escapeHtml(latestDebugIncident?.status || "none")}</strong></div>
        <pre>${escapeHtml(debugIncidentSummary(latestDebugIncident))}</pre>
      </section>
      <section class="deploy-preview-card">
        <div class="inspector-row deploy-row"><span>Recent Debug Failures</span><strong>${escapeHtml(recentDebugFailures.length)}</strong></div>
        <pre>${escapeHtml(recentFailureSummary(recentDebugFailures))}</pre>
      </section>
    </div>
    <div class="lane-list">
      ${nextSteps.length
        ? nextSteps.map((step) => `<div class="lane-note">${escapeHtml(step)}</div>`).join("")
        : `<div class="lane-note">No next steps returned.</div>`}
    </div>
  `;
}

function renderComposer(data) {
  const actions = ["observe", "precheck", "plan", "apply", "rollback", "capture-artifacts"];

  byId("action-strip").innerHTML = actions
    .map(
      (command, index) => `
        <button class="action-button ${index === 0 ? "primary" : ""}" data-action-command="${escapeHtml(command)}" type="button">
          ${escapeHtml(command)}
        </button>
      `
    )
    .join("");

  const actionResult = byId("action-result");

  if (!state.lastAction) {
    actionResult.className = "action-result";
    actionResult.textContent = "No dashboard action has been executed yet.";
  } else {
    actionResult.className = `action-result ${state.lastAction.ok ? "ok" : "error"}`;
    actionResult.textContent = state.lastAction.message;
  }

  byId("composer-suggestions").innerHTML = (data.agents.skills || [])
    .slice(0, 6)
    .map(
      (skill) => `
        <div class="suggestion-pill">
          <strong>${escapeHtml(skill.name)}</strong>
          <span>${skill.has_run_script ? "run.sh" : "reference only"}</span>
        </div>
      `
    )
    .join("");
}

function nextTargetBackend(cellGroup) {
  const targets = cellGroup?.failover_targets || [];
  return targets.find((target) => target !== cellGroup.backend) || targets[0] || cellGroup?.backend || null;
}

function approvalPayload(command) {
  const timestamp = new Date().toISOString();
  const compact = timestamp.replaceAll(/[^0-9]/g, "").slice(0, 14);

  return {
    approved: true,
    approved_by: "dashboard.operator",
    approved_at: timestamp,
    ticket_ref: `DASH-${command.toUpperCase()}-${compact}`,
    source: "dashboard",
    evidence: ["dashboard-action", "operator-composer"]
  };
}

function actionId(prefix) {
  const stamp = new Date().toISOString().replaceAll(/[^0-9]/g, "").slice(0, 14);
  return `${prefix}-${stamp}`;
}

function buildActionPayload(command, data) {
  const cellGroup = findFocusedCellGroup(data);
  const focusedRun = findFocusedRun(data);
  const useFocusedRun = ["apply", "rollback", "capture-artifacts"].includes(command);
  const changeId = useFocusedRun ? focusedRun?.id || actionId("chg-ui") : actionId("chg-ui");

  const payload = {
    command,
    scope: "cell_group",
    cell_group: cellGroup?.id || "cg-001",
    target_backend: nextTargetBackend(cellGroup),
    current_backend: cellGroup?.backend || null,
    change_id: changeId,
    reason: `${command} requested from dashboard`,
    idempotency_key: `${command}-${Date.now()}`,
    dry_run: false,
    ttl: "15m",
    verify_window: { duration: "30s", checks: ["gateway_healthy"] },
    max_blast_radius: "single_cell_group",
    metadata: {
      source: "dashboard",
      dashboard_profile: data.ran.profile
    }
  };

  if (command === "apply" || command === "rollback") {
    payload.approval = approvalPayload(command);
  }

  if (command === "rollback") {
    payload.target_backend = null;
  }

  return payload;
}

async function runAction(command) {
  if (!state.data) {
    return;
  }

  state.lastAction = {
    ok: true,
    message: `Running ${command}...`
  };
  render(state.data);

  try {
    const response = await fetch("/api/actions/run", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(buildActionPayload(command, state.data))
    });
    const payload = await response.json();

    state.lastAction = {
      ok: response.ok,
      message: response.ok
        ? `${command} completed with status ${payload.result.status}`
        : `${command} failed: ${payload.status || "unknown_error"}`
    };

    await refresh();
  } catch (error) {
    state.lastAction = {
      ok: false,
      message: `${command} failed: ${error.message}`
    };
    render(state.data);
  }
}

function buildDeployPayload(mode) {
  return {
    mode,
    config: state.deployForm || {}
  };
}

async function runDeploy(mode) {
  if (!state.data) {
    return;
  }

  state.lastDeploy = {
    mode,
    ok: true,
    message: `${mode} running...`,
    result: null
  };
  render(state.data);

  try {
    const response = await fetch("/api/deploy/run", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(buildDeployPayload(mode))
    });
    const payload = await response.json();

    state.lastDeploy = {
      mode,
      ok: response.ok,
      message: response.ok
        ? `${mode} completed with ${payload.result.preflight?.status || payload.result.status}`
        : `${mode} failed: ${payload.status || "unknown_error"}`,
      result: response.ok ? payload.result : payload
    };

    await refresh();
  } catch (error) {
    state.lastDeploy = {
      mode,
      ok: false,
      message: `${mode} failed: ${error.message}`,
      result: null
    };
    render(state.data);
  }
}

function render(snapshot) {
  state.data = snapshot;
  ensureDeployForm(snapshot);

  const cellGroup = findFocusedCellGroup(snapshot);
  const focusedRun = findFocusedRun(snapshot);
  const focusedContainer = findFocusedContainer(snapshot, cellGroup);
  const evidence = findFocusedEvidence(snapshot, cellGroup, focusedRun);

  if (!state.focusedCellGroupId && cellGroup) {
    state.focusedCellGroupId = cellGroup.id;
  }

  if (!state.focusedRunId && focusedRun) {
    state.focusedRunId = focusedRun.id;
  }

  if (!state.focusedContainerName && focusedContainer) {
    state.focusedContainerName = focusedContainer.name;
  }

  document.title = snapshot.identity.title;

  renderMissionList(snapshot, cellGroup);
  renderRunList(snapshot, focusedRun);
  renderSkillStack(snapshot);
  renderTopbar(snapshot, cellGroup);
  renderBrief(snapshot, cellGroup);
  renderTimeline(snapshot, focusedRun);
  renderRuntimeBoard(snapshot, focusedContainer);
  renderDeployStudio(snapshot);
  renderFocusSummary(snapshot, cellGroup, focusedRun, focusedContainer);
  renderPolicyPanel(snapshot);
  renderNativeContractPanel(focusedRun);
  renderProtocolStatePanel(cellGroup, focusedRun);
  renderRunPanel(focusedRun);
  renderEvidencePanel(evidence);
  renderLanePanel(snapshot, focusedRun);
  renderComposer(snapshot);
}

async function refresh() {
  try {
    const snapshot = await fetchSnapshot();
    render(snapshot);
  } catch (error) {
    console.error(error);
  }
}

document.addEventListener("click", (event) => {
  const missionButton = event.target.closest("[data-cell-group]");

  if (missionButton) {
    state.focusedCellGroupId = missionButton.dataset.cellGroup;
    state.focusedContainerName = null;
    render(state.data);
    return;
  }

  const runButton = event.target.closest("[data-run-id]");

  if (runButton) {
    state.focusedRunId = runButton.dataset.runId;
    render(state.data);
    return;
  }

  const containerButton = event.target.closest("[data-container-name]");

  if (containerButton) {
    state.focusedContainerName = containerButton.dataset.containerName;
    render(state.data);
    return;
  }

  const actionButton = event.target.closest("[data-action-command]");

  if (actionButton) {
    runAction(actionButton.dataset.actionCommand);
    return;
  }

  const deployButton = event.target.closest("[data-deploy-command]");

  if (deployButton) {
    runDeploy(deployButton.dataset.deployCommand);
    return;
  }

  const resetButton = event.target.closest("[data-deploy-reset]");

  if (resetButton) {
    state.deployForm = { ...(state.data?.deploy?.defaults || {}) };
    state.lastDeploy = null;
    render(state.data);
    return;
  }

  const copyButton = event.target.closest("[data-copy-target]");

  if (copyButton) {
    const target = byId(copyButton.dataset.copyTarget);

    if (!target) {
      return;
    }

    copyText(target.textContent || "")
      .then(() => {
        if (state.lastDeploy) {
          state.lastDeploy = {
            ...state.lastDeploy,
            message: `Copied ${copyButton.dataset.copyTarget}`
          };
          render(state.data);
        }
      })
      .catch((error) => {
        if (state.lastDeploy) {
          state.lastDeploy = {
            ...state.lastDeploy,
            ok: false,
            message: `Copy failed: ${error.message}`
          };
          render(state.data);
        }
      });
  }
});

function updateDeployField(event) {
  const field = event.target.closest("[data-deploy-field]");

  if (!field) {
    return;
  }

  if (!state.deployForm) {
    state.deployForm = {};
  }

  const key = field.dataset.deployField;
  state.deployForm[key] = field.type === "checkbox" ? field.checked : field.value;
}

document.addEventListener("input", updateDeployField);
document.addEventListener("change", updateDeployField);

byId("refresh-button").addEventListener("click", refresh);

refresh();
setInterval(refresh, 5000);
