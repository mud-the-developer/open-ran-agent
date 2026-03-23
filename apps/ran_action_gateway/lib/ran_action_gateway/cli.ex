defmodule RanActionGateway.CLI do
  @moduledoc """
  Command-line entrypoint for `bin/ranctl`.
  """

  alias RanActionGateway.Request
  alias RanActionGateway.Runner

  @type result :: {:ok, map()} | {:error, map()} | {:usage, map()}

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    case run(argv) do
      {:usage, payload} ->
        IO.puts(payload.usage)
        System.halt(0)

      {:ok, payload} ->
        IO.puts(JSON.encode!(payload))
        System.halt(0)

      {:error, payload} ->
        IO.puts(JSON.encode!(payload))
        System.halt(1)
    end
  end

  @spec run([String.t()]) :: result()
  def run(argv) do
    with {:ok, command, args} <- parse_command(argv),
         {:ok, opts} <- parse_options(args),
         {:ok, payload} <- load_payload(opts),
         {:ok, change} <- Request.build_change(payload),
         {:ok, response} <- Runner.execute(command, change) do
      {:ok, response}
    end
  end

  @spec usage() :: String.t()
  def usage do
    """
    Usage:
      bin/ranctl <command> [--file PATH | --json STRING]

    Commands:
      precheck
      plan
      apply
      verify
      rollback
      observe
      capture-artifacts
    """
  end

  defp parse_command([arg | rest]) do
    case arg do
      "help" -> {:usage, %{usage: usage()}}
      "-h" -> {:usage, %{usage: usage()}}
      "--help" -> {:usage, %{usage: usage()}}
      _ -> to_command(arg, rest)
    end
  end

  defp parse_command([]), do: {:usage, %{usage: usage()}}

  defp to_command("capture-artifacts", rest), do: {:ok, :capture_artifacts, rest}

  defp to_command(command, rest) do
    case Request.command_from_string(command) do
      {:ok, phase} -> {:ok, phase, rest}
      {:error, payload} -> {:error, Map.put(payload, :usage, usage())}
    end
  end

  defp parse_options(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          file: :string,
          json: :string
        ]
      )

    cond do
      invalid != [] ->
        {:error, %{status: "invalid_cli_options", invalid: invalid, usage: usage()}}

      rest != [] ->
        {:error, %{status: "unexpected_arguments", arguments: rest, usage: usage()}}

      Keyword.has_key?(opts, :file) and Keyword.has_key?(opts, :json) ->
        {:error, %{status: "invalid_cli_options", errors: ["use either --file or --json"]}}

      true ->
        {:ok, opts}
    end
  end

  defp load_payload(opts) do
    cond do
      json = opts[:json] ->
        decode_payload(json)

      file = opts[:file] ->
        with {:ok, body} <- File.read(file) do
          decode_payload(body)
        else
          {:error, reason} ->
            {:error, %{status: "input_read_failed", path: file, errors: [inspect(reason)]}}
        end

      true ->
        {:ok, %{}}
    end
  end

  defp decode_payload(body) do
    with {:ok, payload} <- JSON.decode(body) do
      {:ok, payload}
    else
      {:error, reason} ->
        {:error, %{status: "invalid_json", errors: [inspect(reason)]}}
    end
  end
end
