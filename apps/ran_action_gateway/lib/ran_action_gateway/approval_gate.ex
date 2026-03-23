defmodule RanActionGateway.ApprovalGate do
  @moduledoc """
  Minimal approval cache for bootstrap workflows.
  """

  use GenServer

  def child_spec(initial_state) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [initial_state]}
    }
  end

  def start_link(initial_state) do
    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  def allow(change_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:allow, change_id, metadata})
  end

  def approved?(change_id) do
    GenServer.call(__MODULE__, {:approved?, change_id})
  end

  @impl true
  def init(initial_state) do
    {:ok, Map.new(initial_state)}
  end

  @impl true
  def handle_call({:allow, change_id, metadata}, _from, state) do
    next_state = Map.put(state, change_id, Map.put(metadata, :approved, true))
    {:reply, :ok, next_state}
  end

  def handle_call({:approved?, change_id}, _from, state) do
    {:reply, Map.has_key?(state, change_id), state}
  end
end
