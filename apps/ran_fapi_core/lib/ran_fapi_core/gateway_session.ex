defmodule RanFapiCore.GatewaySession do
  @moduledoc """
  Managed backend gateway session with explicit health and restart semantics.
  """

  use GenServer

  alias RanFapiCore.{Capability, Health, IR, Profile}

  @type state :: %{
          backend: module(),
          profile: RanCore.backend_profile(),
          capability: Capability.t(),
          session_opts: keyword(),
          session: term(),
          cell_group_id: RanCore.cell_group_id() | nil,
          health: Health.t(),
          restart_count: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec capability(GenServer.server()) :: {:ok, Capability.t()}
  def capability(server), do: GenServer.call(server, :capability)

  @spec health(GenServer.server()) :: {:ok, Health.t()}
  def health(server), do: GenServer.call(server, :health)

  @spec submit_slot(GenServer.server(), IR.t()) :: {:ok, map()} | {:error, term()}
  def submit_slot(server, %IR{} = ir), do: GenServer.call(server, {:submit_slot, ir})

  @spec handle_uplink_indication(GenServer.server(), map()) :: :ok | {:error, term()}
  def handle_uplink_indication(server, indication) when is_map(indication),
    do: GenServer.call(server, {:uplink_indication, indication})

  @spec quiesce(GenServer.server(), keyword()) :: :ok | {:error, term()}
  def quiesce(server, opts \\ []), do: GenServer.call(server, {:quiesce, opts})

  @spec resume(GenServer.server()) :: :ok | {:error, term()}
  def resume(server), do: GenServer.call(server, :resume)

  @spec restart(GenServer.server()) :: {:ok, Health.t()} | {:error, term()}
  def restart(server), do: GenServer.call(server, :restart)

  @impl true
  def init(opts) do
    cell_group_id = Keyword.get(opts, :cell_group_id)
    profile = Keyword.fetch!(opts, :profile)
    session_opts = Keyword.drop(opts, [:name])

    with {:ok, backend} <- Profile.backend_module(profile),
         {:ok, capability} <- Profile.capabilities(profile),
         {:ok, session} <- backend.open_session(session_opts),
         :ok <- maybe_activate_cell(backend, session, cell_group_id) do
      {:ok,
       %{
         backend: backend,
         profile: profile,
         capability: capability,
         session_opts: session_opts,
         session: session,
         cell_group_id: cell_group_id,
         health: Health.new(:healthy, session_status: :active),
         restart_count: 0
       }}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:capability, _from, state) do
    {:reply, {:ok, state.capability}, state}
  end

  def handle_call(:health, _from, state) do
    {:reply, {:ok, state.health}, state}
  end

  def handle_call({:submit_slot, %IR{} = ir}, _from, state) do
    case state.health.session_status do
      :quiesced ->
        {:reply, {:error, :session_quiesced}, state}

      _ ->
        with :ok <- IR.validate(ir),
             :ok <- Capability.compatible?(state.capability, state.profile, IR.message_kinds(ir)),
             :ok <- state.backend.submit_slot(state.session, ir),
             {:ok, backend_health} <- state.backend.health(state.session) do
          health = %{backend_health | restart_count: state.restart_count}

          {:reply,
           {:ok,
            %{status: :submitted, ir: ir, health: health, backend_capabilities: state.capability}},
           %{state | health: health}}
        else
          {:error, reason} ->
            failed = Health.transition(state.health, :failed, reason: inspect(reason))
            {:reply, {:error, reason}, %{state | health: failed}}
        end
    end
  end

  def handle_call({:uplink_indication, indication}, _from, state) do
    with :ok <- state.backend.handle_uplink_indication(state.session, indication),
         {:ok, backend_health} <- state.backend.health(state.session) do
      health = %{backend_health | restart_count: state.restart_count}
      {:reply, :ok, %{state | health: health}}
    else
      {:error, reason} ->
        failed = Health.transition(state.health, :failed, reason: inspect(reason))
        {:reply, {:error, reason}, %{state | health: failed}}
    end
  end

  def handle_call({:quiesce, opts}, _from, state) do
    case state.backend.quiesce(state.session, opts) do
      :ok ->
        desired_health =
          Health.transition(state.health, :draining,
            reason: Keyword.get(opts, :reason, "quiesced"),
            session_status: :quiesced
          )

        with {:ok, backend_health} <- state.backend.health(state.session) do
          health = merge_backend_checks(desired_health, backend_health, state.restart_count)

          {:reply, :ok, %{state | health: health}}
        else
          {:error, reason} ->
            failed = Health.transition(state.health, :failed, reason: inspect(reason))
            {:reply, {:error, reason}, %{state | health: failed}}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:resume, _from, state) do
    case state.backend.resume(state.session) do
      :ok ->
        desired_health =
          Health.transition(state.health, :healthy, reason: nil, session_status: :active)

        with {:ok, backend_health} <- state.backend.health(state.session) do
          health = merge_backend_checks(desired_health, backend_health, state.restart_count)
          {:reply, :ok, %{state | health: health}}
        else
          {:error, reason} ->
            failed = Health.transition(state.health, :failed, reason: inspect(reason))
            {:reply, {:error, reason}, %{state | health: failed}}
        end

      {:error, reason} ->
        failed = Health.transition(state.health, :failed, reason: inspect(reason))
        {:reply, {:error, reason}, %{state | health: failed}}
    end
  end

  def handle_call(:restart, _from, state) do
    with :ok <- safe_terminate(state.backend, state.session),
         {:ok, session} <- state.backend.open_session(state.session_opts),
         :ok <- maybe_activate_cell(state.backend, session, state.cell_group_id),
         {:ok, backend_health} <- state.backend.health(session) do
      restart_count = state.restart_count + 1

      desired_health =
        Health.new(:healthy,
          session_status: :active,
          restart_count: restart_count,
          reason: "gateway session restarted"
        )

      health = merge_backend_checks(desired_health, backend_health, restart_count)

      {:reply, {:ok, health},
       %{state | session: session, health: health, restart_count: restart_count}}
    else
      {:error, reason} ->
        failed = Health.transition(state.health, :failed, reason: inspect(reason))
        {:reply, {:error, reason}, %{state | health: failed}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    safe_terminate(state.backend, state.session)
    :ok
  end

  defp maybe_activate_cell(_backend, _session, nil), do: :ok

  defp maybe_activate_cell(backend, session, cell_group_id),
    do: backend.activate_cell(session, cell_group_id: cell_group_id)

  defp safe_terminate(backend, session) do
    case backend.terminate(session) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp merge_backend_checks(%Health{} = desired_health, %Health{} = backend_health, restart_count) do
    %{
      desired_health
      | checks: Map.merge(desired_health.checks, backend_health.checks),
        restart_count: restart_count
    }
  end
end
