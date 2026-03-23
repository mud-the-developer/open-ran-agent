defmodule RanConfig.ChangePolicyTest do
  use ExUnit.Case, async: false

  setup do
    original_cell_groups = Application.get_env(:ran_config, :cell_groups)

    on_exit(fn ->
      Application.put_env(:ran_config, :cell_groups, original_cell_groups, persistent: true)
    end)

    :ok
  end

  test "returns allowed targets and rollback target for a configured cell group" do
    Application.put_env(
      :ran_config,
      :cell_groups,
      [
        %{
          id: "cg-001",
          du: "du-001",
          backend: :stub_fapi_profile,
          failover_targets: [:local_fapi_profile],
          scheduler: :cpu_scheduler
        }
      ],
      persistent: true
    )

    assert {:ok, policy} = RanConfig.backend_switch_policy("cg-001", :local_fapi_profile)
    assert policy.current_backend == :stub_fapi_profile
    assert policy.rollback_target == :stub_fapi_profile
    assert policy.allowed_targets == [:stub_fapi_profile, :local_fapi_profile]
    assert policy.target_preprovisioned == true
  end

  test "rejects targets that are not pre-provisioned" do
    Application.put_env(
      :ran_config,
      :cell_groups,
      [
        %{
          id: "cg-001",
          du: "du-001",
          backend: :stub_fapi_profile,
          failover_targets: [:local_fapi_profile],
          scheduler: :cpu_scheduler
        }
      ],
      persistent: true
    )

    assert {:error, %{status: "policy_denied", policy: policy}} =
             RanConfig.backend_switch_policy("cg-001", :aerial_fapi_profile)

    assert policy.allowed_targets == ["stub_fapi_profile", "local_fapi_profile"]
    assert policy.target_preprovisioned == false
  end
end
