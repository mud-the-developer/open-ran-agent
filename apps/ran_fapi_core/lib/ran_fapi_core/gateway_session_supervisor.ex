defmodule RanFapiCore.GatewaySessionSupervisor do
  @moduledoc """
  Supervises backend gateway sessions separately from DU-high orchestration trees.
  """

  use DynamicSupervisor

  def start_link(arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_session(keyword()) :: DynamicSupervisor.on_start_child()
  def start_session(opts) do
    child_spec = {RanFapiCore.GatewaySession, put_name(opts)}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  defp put_name(opts) do
    Keyword.put_new_lazy(opts, :name, fn ->
      {:via, Registry,
       {RanFapiCore.ProfileRegistry,
        {Keyword.get(opts, :cell_group_id, "adhoc"), Keyword.fetch!(opts, :profile)}}}
    end)
  end
end
