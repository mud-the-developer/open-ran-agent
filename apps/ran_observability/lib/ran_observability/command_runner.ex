defmodule RanObservability.CommandRunner do
  @moduledoc """
  Small wrapper around shell execution so snapshot collection remains testable.
  """

  @callback run(Path.t(), [String.t()], keyword()) :: {binary(), non_neg_integer()}

  @spec run(Path.t(), [String.t()], keyword()) :: {binary(), non_neg_integer()}
  def run(command, args, opts \\ []) do
    runner = Application.get_env(:ran_observability, :command_runner, __MODULE__.System)
    runner.run(command, args, opts)
  end
end

defmodule RanObservability.CommandRunner.System do
  @moduledoc false

  @behaviour RanObservability.CommandRunner

  @impl true
  def run(command, args, opts) do
    System.cmd(command, args, opts)
  end
end
