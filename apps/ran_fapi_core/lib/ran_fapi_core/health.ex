defmodule RanFapiCore.Health do
  @moduledoc """
  Explicit health state model for backend gateway sessions.
  """

  @enforce_keys [:state]
  defstruct [
    :state,
    :reason,
    :last_transition_at,
    checks: %{},
    session_status: :idle,
    restart_count: 0
  ]

  @type state :: :healthy | :degraded | :draining | :failed

  @type t :: %__MODULE__{
          state: state(),
          reason: String.t() | nil,
          last_transition_at: String.t(),
          checks: map(),
          session_status: atom(),
          restart_count: non_neg_integer()
        }

  @spec new(state(), keyword()) :: t()
  def new(state, opts \\ []) when state in [:healthy, :degraded, :draining, :failed] do
    %__MODULE__{
      state: state,
      reason: Keyword.get(opts, :reason),
      checks: Keyword.get(opts, :checks, %{}),
      session_status: Keyword.get(opts, :session_status, :idle),
      restart_count: Keyword.get(opts, :restart_count, 0),
      last_transition_at: now_iso8601()
    }
  end

  @spec transition(t(), state(), keyword()) :: t()
  def transition(%__MODULE__{} = health, state, opts \\ [])
      when state in [:healthy, :degraded, :draining, :failed] do
    %__MODULE__{
      health
      | state: state,
        reason: Keyword.get(opts, :reason, health.reason),
        checks: Keyword.get(opts, :checks, health.checks),
        session_status: Keyword.get(opts, :session_status, health.session_status),
        restart_count: Keyword.get(opts, :restart_count, health.restart_count),
        last_transition_at: now_iso8601()
    }
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
