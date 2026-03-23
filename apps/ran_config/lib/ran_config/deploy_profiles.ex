defmodule RanConfig.DeployProfiles do
  @moduledoc """
  OCUDU-inspired deployment profiles for target-host bring-up and operations UX.
  """

  @profiles %{
    "stable_ops" => %{
      title: "Stable Ops",
      description:
        "Conservative target-host profile with strict host probe, local-first dashboard exposure, and deterministic fetchback.",
      stability_tier: "conservative",
      exposure: "ssh_tunnel_first",
      recommended_for: ["production-like labs", "change windows", "deterministic rollback drills"],
      overlays: [
        "layered_config_preview",
        "strict_host_probe",
        "effective_config_export",
        "remote_fetchback"
      ],
      operator_steps: [
        "Generate repo-local preview and review effective config.",
        "Set target_host and keep dashboard bound to 127.0.0.1.",
        "Run host preflight before any remote apply.",
        "Ship the bundle only after preflight evidence is clean.",
        "Fetch evidence back after each remote ranctl run."
      ],
      config_overrides: %{
        strict_host_probe: true,
        pull_images: false,
        dashboard_host: "127.0.0.1",
        dashboard_port: "4050",
        mix_env: "prod"
      },
      ops_preferences: %{
        evidence_capture: "standard",
        dashboard_surface: "ssh_tunnel_first",
        remote_fetchback: true,
        preflight_gate: "strict"
      }
    },
    "troubleshoot" => %{
      title: "Troubleshoot",
      description:
        "Incident-response profile with expanded evidence capture, debugger-friendly dashboard exposure, and the same strict host gate.",
      stability_tier: "guarded",
      exposure: "operator_shared",
      recommended_for: ["incident triage", "field debugging", "evidence-heavy investigations"],
      overlays: [
        "layered_config_preview",
        "strict_host_probe",
        "verbose_evidence",
        "remote_fetchback"
      ],
      operator_steps: [
        "Keep strict host probe enabled even during incident work.",
        "Open the dashboard only to the scoped operator network.",
        "Run preview, then preflight, before collecting extra evidence remotely.",
        "Use verbose fetchback after each investigate or rollback step."
      ],
      config_overrides: %{
        strict_host_probe: true,
        pull_images: false,
        dashboard_host: "0.0.0.0",
        dashboard_port: "4050",
        mix_env: "prod"
      },
      ops_preferences: %{
        evidence_capture: "verbose",
        dashboard_surface: "operator_shared",
        remote_fetchback: true,
        preflight_gate: "strict"
      }
    },
    "lab_attach" => %{
      title: "Lab Attach",
      description:
        "Faster lab bring-up profile that keeps strict probing but opens the dashboard bind and allows image pulls during apply.",
      stability_tier: "expedite",
      exposure: "operator_shared",
      recommended_for: ["shared lab bring-up", "attach rehearsals", "image-refresh testing"],
      overlays: [
        "layered_config_preview",
        "strict_host_probe",
        "fast_lab_bringup",
        "effective_config_export"
      ],
      operator_steps: [
        "Preview and verify the attach topology first.",
        "Allow image pulls only when the lab host is isolated.",
        "Run preflight immediately before apply to avoid stale host assumptions.",
        "Capture artifacts after each attach attempt."
      ],
      config_overrides: %{
        strict_host_probe: true,
        pull_images: true,
        dashboard_host: "0.0.0.0",
        dashboard_port: "4050",
        mix_env: "prod"
      },
      ops_preferences: %{
        evidence_capture: "standard",
        dashboard_surface: "operator_shared",
        remote_fetchback: true,
        preflight_gate: "strict"
      }
    }
  }

  @spec default_profile() :: String.t()
  def default_profile, do: "stable_ops"

  @spec catalog() :: [map()]
  def catalog do
    @profiles
    |> Enum.map(fn {name, profile} ->
      %{
        name: name,
        title: profile.title,
        description: profile.description,
        stability_tier: profile.stability_tier,
        exposure: profile.exposure,
        recommended_for: profile.recommended_for,
        overlays: profile.overlays,
        operator_steps: profile.operator_steps,
        ops_preferences: profile.ops_preferences
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @spec profile(String.t() | nil) :: {:ok, map()} | {:error, map()}
  def profile(name) when name in [nil, ""], do: profile(default_profile())

  def profile(name) do
    case Map.fetch(@profiles, to_string(name)) do
      {:ok, profile} ->
        {:ok,
         %{
           name: to_string(name),
           title: profile.title,
           description: profile.description,
           stability_tier: profile.stability_tier,
           exposure: profile.exposure,
           recommended_for: profile.recommended_for,
           overlays: profile.overlays,
           operator_steps: profile.operator_steps,
           config_overrides: profile.config_overrides,
           ops_preferences: profile.ops_preferences
         }}

      :error ->
        {:error,
         %{
           status: "unknown_deploy_profile",
           deploy_profile: name,
           known_profiles: @profiles |> Map.keys() |> Enum.sort()
         }}
    end
  end

  @spec apply_config(map(), String.t() | nil) :: {:ok, map()} | {:error, map()}
  def apply_config(config, profile_name) when is_map(config) do
    with {:ok, profile} <- profile(profile_name) do
      {:ok,
       config
       |> Map.merge(profile.config_overrides)
       |> Map.put(:deploy_profile, profile.name)}
    end
  end

  @spec summary(String.t() | nil) :: map()
  def summary(profile_name) do
    case profile(profile_name) do
      {:ok, profile} ->
        Map.take(profile, [
          :name,
          :title,
          :description,
          :stability_tier,
          :exposure,
          :recommended_for,
          :overlays,
          :operator_steps,
          :ops_preferences
        ])

      {:error, payload} ->
        %{
          name: to_string(profile_name || default_profile()),
          title: "Unknown Profile",
          description: "The selected deploy profile is not registered.",
          stability_tier: "unknown",
          exposure: "unknown",
          recommended_for: [],
          overlays: [],
          operator_steps: [],
          ops_preferences: %{},
          error: payload
        }
    end
  end
end
