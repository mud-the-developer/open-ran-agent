defmodule RanCore.Topology do
  @moduledoc """
  Minimal topology cache used by bootstrap code and future runtime loaders.
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

  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  def fetch(key) do
    GenServer.call(__MODULE__, {:fetch, key})
  end

  @impl true
  def init(initial_state) do
    {:ok, Map.new(initial_state)}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    next_state = Map.put(state, key, value)
    {:reply, :ok, next_state}
  end

  def handle_call({:fetch, key}, _from, state) do
    {:reply, Map.fetch(state, key), state}
  end
end
