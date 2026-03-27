defmodule RanFapiCore.Backends.AerialBackend do
  @moduledoc """
  Bootstrap clean-room contract adapter for future NVIDIA Aerial integration.

  This module intentionally exposes only the shared contract and does not model
  vendor internals.
  """

  alias RanFapiCore.Backends.PortBackedBackend

  @behaviour RanFapiCore.Backends.Adapter

  @impl true
  def capabilities do
    PortBackedBackend.capabilities(:aerial_fapi_profile, :aerial,
      metadata: %{
        adapter_owner: "clean_room_scaffold",
        integration_boundary: "clean_room_vendor_profile",
        vendor_surface: "opaque",
        support_posture: "bounded_clean_room_runtime",
        promotion_state: "bounded_clean_room_runtime",
        declared_target_profile: "aerial_clean_room_runtime_v1",
        supported_claims: [
          "clean_room_session_lifecycle",
          "strict_host_probe_gating",
          "health_drain_resume_restart",
          "deterministic_verify_and_rollback_artifacts"
        ],
        unsupported_claims: [
          "vendor_device_bringup",
          "attach_plus_ping_proof",
          "production_timing_guarantee"
        ],
        verify_evidence_refs: [
          "apps/ran_fapi_core/test/ran_fapi_core/native_gateway_contract_test.exs",
          "apps/ran_fapi_core/test/ran_fapi_core/native_gateway_transport_state_test.exs"
        ],
        rollback_evidence_refs: [
          "apps/ran_fapi_core/test/ran_fapi_core/native_gateway_contract_test.exs",
          "apps/ran_fapi_core/test/ran_fapi_core/native_gateway_transport_state_test.exs"
        ],
        health_model_ref: "docs/architecture/04-du-high-southbound-contract.md",
        failure_domain_refs: [
          "docs/architecture/03-failure-domains.md",
          "docs/architecture/04-du-high-southbound-contract.md"
        ],
        future_expansion_requirements: [
          "vendor_device_bringup",
          "real_aerial_attach_plus_ping",
          "production_timing_guarantee"
        ]
      }
    )
  end

  @impl true
  def open_session(opts), do: PortBackedBackend.open_session(:aerial_fapi_profile, :aerial, opts)

  @impl true
  def activate_cell(session, opts), do: PortBackedBackend.activate_cell(session, opts)

  @impl true
  def submit_slot(session, ir), do: PortBackedBackend.submit_slot(session, ir)

  @impl true
  def handle_uplink_indication(session, indication),
    do: PortBackedBackend.handle_uplink_indication(session, indication)

  @impl true
  def health(session), do: PortBackedBackend.health(session)

  @impl true
  def quiesce(session, opts), do: PortBackedBackend.quiesce(session, opts)

  @impl true
  def resume(session), do: PortBackedBackend.resume(session)

  @impl true
  def terminate(session), do: PortBackedBackend.terminate(session)
end
