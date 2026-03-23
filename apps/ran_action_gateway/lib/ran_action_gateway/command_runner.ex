defmodule RanActionGateway.CommandRunner do
  @moduledoc """
  Small wrapper over external command execution so runtime orchestration remains testable.
  """

  @callback run(Path.t(), [String.t()], keyword()) ::
              {Collectable.t(), non_neg_integer()} | {binary(), non_neg_integer()}

  @spec run(Path.t(), [String.t()], keyword()) :: {binary(), non_neg_integer()}
  def run(command, args, opts \\ []) do
    runner = Application.get_env(:ran_action_gateway, :command_runner, __MODULE__.System)
    runner.run(command, args, opts)
  end
end

defmodule RanActionGateway.CommandRunner.System do
  @moduledoc false

  @behaviour RanActionGateway.CommandRunner

  @impl true
  def run(command, args, opts) do
    System.cmd(command, args, Keyword.merge([stderr_to_stdout: true], opts))
  end
end
