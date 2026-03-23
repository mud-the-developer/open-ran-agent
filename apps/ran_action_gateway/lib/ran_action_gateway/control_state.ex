defmodule RanActionGateway.ControlState do
  @moduledoc """
  In-memory operational control state for attach freeze and cell-group drain flow.
  """

  use GenServer

  alias RanActionGateway.Store

  @attach_actions ~w(activate release)
  @drain_actions ~w(start complete clear)
  @control_checks ~w(attach_freeze_active cell_group_drained drain_active drain_idle)

  @type snapshot :: map()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec snapshot(String.t() | nil) :: snapshot() | nil
  def snapshot(nil), do: nil
  def snapshot(cell_group_id), do: GenServer.call(__MODULE__, {:snapshot, cell_group_id})

  @spec apply_intents(String.t() | nil, map(), keyword()) :: {:ok, snapshot() | nil}
  def apply_intents(cell_group_id, control, context \\ [])
  def apply_intents(nil, _control, _context), do: {:ok, nil}

  def apply_intents(cell_group_id, control, context) when is_map(control) do
    GenServer.call(
      __MODULE__,
      {:apply_intents, cell_group_id, normalize_control(control), context}
    )
  end

  @spec check(String.t() | nil, String.t()) :: boolean()
  def check(nil, _check_name), do: false

  def check(cell_group_id, check_name) when is_binary(check_name) do
    GenServer.call(__MODULE__, {:check, cell_group_id, check_name})
  end

  @spec supported_checks() :: [String.t()]
  def supported_checks, do: @control_checks

  @spec reset() :: :ok
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:snapshot, cell_group_id}, _from, state) do
    snapshot =
      state
      |> Map.get(cell_group_id)
      |> case do
        nil -> load_snapshot(cell_group_id)
        snapshot -> snapshot
      end

    {:reply, snapshot, Map.put(state, cell_group_id, snapshot)}
  end

  def handle_call({:apply_intents, cell_group_id, control, context}, _from, state) do
    snapshot =
      state
      |> Map.get(cell_group_id, load_snapshot(cell_group_id))
      |> apply_attach_intent(control["attach_freeze"], context)
      |> apply_drain_intent(control["drain"], context)
      |> Map.put("updated_at", now_iso8601())

    Store.write_json(Store.control_state_path(cell_group_id), snapshot)

    {:reply, {:ok, snapshot}, Map.put(state, cell_group_id, snapshot)}
  end

  def handle_call({:check, cell_group_id, check_name}, _from, state) do
    snapshot = Map.get(state, cell_group_id, load_snapshot(cell_group_id))
    {:reply, check_snapshot(snapshot, check_name), Map.put(state, cell_group_id, snapshot)}
  end

  def handle_call(:reset, _from, _state) do
    Store.artifact_root()
    |> Path.join("control_state/*.json")
    |> Path.wildcard()
    |> Enum.each(&File.rm_rf!/1)

    {:reply, :ok, %{}}
  end

  defp normalize_control(control) do
    Enum.reduce(control, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp default_snapshot(cell_group_id) do
    timestamp = now_iso8601()

    %{
      "cell_group" => cell_group_id,
      "attach_freeze" => control_entry("inactive", timestamp),
      "drain" => control_entry("idle", timestamp),
      "updated_at" => timestamp
    }
  end

  defp load_snapshot(cell_group_id) do
    case Store.read_json(Store.control_state_path(cell_group_id)) do
      {:ok, payload} when is_map(payload) -> payload
      _ -> default_snapshot(cell_group_id)
    end
  end

  defp apply_attach_intent(snapshot, action, _context) when action not in @attach_actions,
    do: snapshot

  defp apply_attach_intent(snapshot, action, context) do
    status = if action == "activate", do: "active", else: "inactive"
    put_entry(snapshot, "attach_freeze", status, context)
  end

  defp apply_drain_intent(snapshot, action, _context) when action not in @drain_actions,
    do: snapshot

  defp apply_drain_intent(snapshot, action, context) do
    status =
      case action do
        "start" -> "draining"
        "complete" -> "drained"
        "clear" -> "idle"
      end

    put_entry(snapshot, "drain", status, context)
  end

  defp put_entry(snapshot, key, status, context) do
    Map.put(snapshot, key, control_entry(status, now_iso8601(), context))
  end

  defp control_entry(status, timestamp, context \\ []) do
    %{
      "status" => status,
      "reason" => Keyword.get(context, :reason),
      "source_change_id" => Keyword.get(context, :change_id),
      "source_command" => context |> Keyword.get(:command) |> maybe_to_string(),
      "changed_at" => timestamp
    }
  end

  defp check_snapshot(snapshot, "attach_freeze_active") do
    get_in(snapshot, ["attach_freeze", "status"]) == "active"
  end

  defp check_snapshot(snapshot, "cell_group_drained") do
    get_in(snapshot, ["drain", "status"]) == "drained"
  end

  defp check_snapshot(snapshot, "drain_active") do
    get_in(snapshot, ["drain", "status"]) in ["draining", "drained"]
  end

  defp check_snapshot(snapshot, "drain_idle") do
    get_in(snapshot, ["drain", "status"]) == "idle"
  end

  defp check_snapshot(_snapshot, _check_name), do: false

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value), do: value

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
