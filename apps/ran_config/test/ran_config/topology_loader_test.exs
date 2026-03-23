defmodule RanConfig.TopologyLoaderTest do
  use ExUnit.Case, async: false

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ran-topology-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)

    original_env = Application.get_all_env(:ran_config)

    on_exit(fn ->
      current_env = Application.get_all_env(:ran_config)

      current_env
      |> Keyword.keys()
      |> Kernel.--(Keyword.keys(original_env))
      |> Enum.each(&Application.delete_env(:ran_config, &1, persistent: true))

      Enum.each(original_env, fn {key, value} ->
        Application.put_env(:ran_config, key, value, persistent: true)
      end)

      if Process.whereis(RanConfig.ProfileCache) do
        RanConfig.ProfileCache.put(:profile, Keyword.get(original_env, :repo_profile, :bootstrap))
        RanConfig.ProfileCache.put(:topology_source, Keyword.get(original_env, :topology_source))
      end

      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  test "loads and normalizes a single-du topology file", %{tmp_dir: tmp_dir} do
    path = write_topology_file(tmp_dir, valid_topology())

    assert {:ok, env} = RanConfig.TopologyLoader.load_file(path)
    assert env[:repo_profile] == :lab_single_du_json
    assert env[:default_backend] == :stub_fapi_profile
    assert env[:scheduler_adapter] == :cpu_scheduler
    assert [%{backend: :stub_fapi_profile, scheduler: :cpu_scheduler}] = env[:cell_groups]
  end

  test "applying a topology file updates the active config profile", %{tmp_dir: tmp_dir} do
    path = write_topology_file(tmp_dir, valid_topology())

    assert {:ok, report} = RanConfig.load_topology(path)
    assert report.status == :ok
    assert report.topology_source == Path.expand(path)
    assert RanConfig.current_profile() == :lab_single_du_json
    assert RanConfig.topology_source() == Path.expand(path)
    assert [%{id: "cg-json-001"}] = RanConfig.cell_groups()
  end

  test "invalid topology files are rejected before application", %{tmp_dir: tmp_dir} do
    path =
      write_topology_file(tmp_dir, %{
        "repo_profile" => "broken_lab",
        "default_backend" => "stub_fapi_profile",
        "scheduler_adapter" => "cpu_scheduler",
        "cell_groups" => [
          %{
            "id" => "cg-json-001",
            "du" => "du-json-001",
            "failover_targets" => ["local_fapi_profile"],
            "scheduler" => "cpu_scheduler"
          }
        ]
      })

    assert {:error, %{status: "invalid_topology", errors: errors}} = RanConfig.load_topology(path)
    assert %{field: "cell_group", message: "cg-json-001 backend must be supported"} in errors
  end

  defp write_topology_file(tmp_dir, payload) do
    path = Path.join(tmp_dir, "single_du_topology.json")
    File.write!(path, JSON.encode!(payload))
    path
  end

  defp valid_topology do
    %{
      "repo_profile" => "lab_single_du_json",
      "default_backend" => "stub_fapi_profile",
      "scheduler_adapter" => "cpu_scheduler",
      "cell_groups" => [
        %{
          "id" => "cg-json-001",
          "du" => "du-json-001",
          "backend" => "stub_fapi_profile",
          "failover_targets" => ["local_fapi_profile", "aerial_fapi_profile"],
          "scheduler" => "cpu_scheduler",
          "oai_runtime" => %{
            "mode" => "docker_compose_rfsim_f1",
            "repo_root" => "/opt/openairinterface5g"
          }
        }
      ]
    }
  end
end
