import Config

oai_repo_root = System.get_env("OAI_REPO_ROOT", "/opt/openairinterface5g")
oai_conf_root = Path.join(oai_repo_root, "ci-scripts/conf_files")

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:application, :change_id, :cell_group, :incident_id]

config :ran_config,
  repo_profile: :bootstrap,
  default_backend: :stub_fapi_profile,
  scheduler_adapter: :cpu_scheduler,
  cell_groups: [
    %{
      id: "cg-001",
      du: "du-bootstrap-001",
      backend: :stub_fapi_profile,
      failover_targets: [:local_fapi_profile, :aerial_fapi_profile],
      scheduler: :cpu_scheduler,
      oai_runtime: %{
        mode: :docker_compose_rfsim_f1,
        repo_root: oai_repo_root,
        du_conf_path: Path.join(oai_conf_root, "gnb-du.sa.band78.106prb.rfsim.conf"),
        cucp_conf_path: Path.join(oai_conf_root, "gnb-cucp.sa.f1.conf"),
        cuup_conf_path: Path.join(oai_conf_root, "gnb-cuup.sa.f1.conf")
      }
    }
  ]

config :ran_action_gateway,
  approval_mode: :explicit_gate,
  max_default_verify_window_ms: 30_000,
  oai_runtime_defaults: %{
    mode: :docker_compose_rfsim_f1,
    project_name_prefix: "ran-oai-du",
    gnb_image: "oaisoftwarealliance/oai-gnb:develop",
    cuup_image: "oaisoftwarealliance/oai-nr-cuup:develop",
    pull_images: true
  }

config :ran_fapi_core,
  canonical_ir_version: "0.1",
  gateway_mode: :port_sidecar

config :ran_observability,
  dashboard_host: "127.0.0.1",
  dashboard_port: 4050
