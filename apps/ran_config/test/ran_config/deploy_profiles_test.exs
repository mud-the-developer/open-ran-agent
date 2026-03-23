defmodule RanConfig.DeployProfilesTest do
  use ExUnit.Case, async: true

  alias RanConfig.DeployProfiles

  test "catalog exposes stable ops as the default profile" do
    assert DeployProfiles.default_profile() == "stable_ops"

    assert Enum.any?(DeployProfiles.catalog(), fn profile ->
             profile.name == "stable_ops" and profile.stability_tier == "conservative" and
               "remote_fetchback" in profile.overlays and
               "production-like labs" in profile.recommended_for and
               length(profile.operator_steps) >= 3
           end)
  end

  test "apply_config merges profile overrides into the deploy config" do
    assert {:ok, config} =
             DeployProfiles.apply_config(
               %{dashboard_host: "0.0.0.0", strict_host_probe: false},
               "stable_ops"
             )

    assert config.deploy_profile == "stable_ops"
    assert config.dashboard_host == "127.0.0.1"
    assert config.strict_host_probe == true
  end
end
