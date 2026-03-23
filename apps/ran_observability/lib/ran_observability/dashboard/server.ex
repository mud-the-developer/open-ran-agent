defmodule RanObservability.Dashboard.Server do
  @moduledoc false

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    Task.start_link(fn -> listen(opts) end)
  end

  defp listen(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)

    {:ok, socket} =
      :gen_tcp.listen(port, [
        :binary,
        active: false,
        packet: :raw,
        reuseaddr: true,
        ip: host
      ])

    accept_loop(socket)
  end

  defp accept_loop(socket) do
    {:ok, client} = :gen_tcp.accept(socket)

    Task.Supervisor.start_child(RanObservability.ArtifactSupervisor, fn ->
      serve_client(client)
    end)

    accept_loop(socket)
  end

  defp serve_client(socket) do
    case recv_request(socket) do
      {:ok, request} ->
        {status, content_type, body} =
          RanObservability.Dashboard.Router.response_for(
            request.method,
            request.path,
            request.body
          )

        response = build_response(status, content_type, body)
        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  defp recv_request(socket), do: recv_request(socket, "")

  defp recv_request(socket, buffer) do
    case parse_request(buffer) do
      {:ok, request} ->
        {:ok, request}

      :more ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, chunk} -> recv_request(socket, buffer <> chunk)
          error -> error
        end
    end
  end

  defp parse_request(buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      {header_end, 4} ->
        header_size = header_end + 4
        headers = binary_part(buffer, 0, header_end)
        body_size = byte_size(buffer) - header_size
        content_length = content_length(headers)

        if body_size < content_length do
          :more
        else
          body = binary_part(buffer, header_size, content_length)
          {:ok, build_request(headers, body)}
        end

      :nomatch ->
        :more
    end
  end

  defp build_request(headers, body) do
    [request_line | header_lines] = String.split(headers, "\r\n", trim: true)
    {method, path} = parse_request_line(request_line)

    %{
      method: method,
      path: path,
      headers: parse_headers(header_lines),
      body: body
    }
  end

  defp parse_request_line(request_line) do
    case String.split(request_line, " ", parts: 3) do
      [method, path | _rest] ->
        {method, String.split(path, "?", parts: 2) |> hd()}

      _ ->
        {"GET", "/"}
    end
  end

  defp parse_headers(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.downcase(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp content_length(headers) do
    headers
    |> String.split("\r\n", trim: true)
    |> Enum.find_value(0, fn line ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          if String.downcase(key) == "content-length" do
            String.trim(value) |> String.to_integer()
          end

        _ ->
          nil
      end
    end)
  end

  defp build_response(status, content_type, body) do
    [
      "HTTP/1.1 ",
      Integer.to_string(status),
      " ",
      reason_phrase(status),
      "\r\n",
      "content-type: ",
      content_type,
      "\r\n",
      "content-length: ",
      Integer.to_string(byte_size(body)),
      "\r\n",
      "cache-control: no-store\r\n",
      "connection: close\r\n\r\n",
      body
    ]
  end

  defp reason_phrase(200), do: "OK"
  defp reason_phrase(405), do: "Method Not Allowed"
  defp reason_phrase(422), do: "Unprocessable Entity"
  defp reason_phrase(404), do: "Not Found"
  defp reason_phrase(_status), do: "OK"
end
