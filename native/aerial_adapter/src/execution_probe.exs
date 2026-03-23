defmodule AerialAdapter.ExecutionProbe do
  def initial_state do
    %{
      handshake_ref: nil,
      handshake_state: "idle",
      handshake_attempts: 0,
      last_handshake_at: nil,
      strict_host_probe: false,
      activation_gate: "warn_only",
      handshake_target: nil,
      probe_evidence_ref: nil,
      probe_checked_at: nil,
      probe_required_resources: [],
      probe_observations: %{},
      host_probe_ref: nil,
      host_probe_status: "unknown",
      host_probe_mode: "clean_room",
      host_probe_failures: [],
      vendor_socket_path: nil,
      vendor_socket_present: nil,
      vendor_socket_usable: nil,
      device_manifest_path: nil,
      device_manifest_present: nil,
      device_manifest_ready: nil,
      cuda_visible_devices: nil,
      cuda_visible_devices_present: nil,
      cuda_visible_devices_ready: nil,
      probe_failure_count: 0
    }
  end

  def open_session(state) do
    execution_lane = state.execution_lane || "gpu_batch"
    vendor_surface = state.vendor_surface || "opaque"
    session_payload = state.session_payload || %{}
    now = now_iso8601()
    vendor_socket_path = Map.get(session_payload, "vendor_socket_path")
    device_manifest_path = Map.get(session_payload, "device_manifest_path")
    cuda_visible_devices = Map.get(session_payload, "cuda_visible_devices")
    strict_host_probe = truthy?(Map.get(session_payload, "strict_host_probe"))
    activation_gate = if strict_host_probe, do: "strict", else: "warn_only"

    vendor_socket_present = optional_path_present(vendor_socket_path)
    device_manifest_present = optional_path_present(device_manifest_path)
    cuda_visible_devices_present = env_value_present?(cuda_visible_devices)
    vendor_socket_observations = path_observations(vendor_socket_path)
    device_manifest_observations = manifest_observations(device_manifest_path)
    cuda_observations = cuda_observations(cuda_visible_devices)
    vendor_socket_usable = path_usable?(vendor_socket_observations)
    device_manifest_ready = manifest_ready?(device_manifest_observations)
    cuda_visible_devices_ready = cuda_ready?(cuda_observations)

    probe_observations =
      probe_observations(
        vendor_socket_observations,
        device_manifest_observations,
        cuda_observations
      )

    host_probe_failures =
      []
      |> maybe_add_failure(vendor_socket_present == false, "missing_vendor_socket")
      |> maybe_add_failure(
        vendor_socket_present == true and vendor_socket_usable == false,
        "vendor_socket_not_usable"
      )
      |> maybe_add_failure(device_manifest_present == false, "missing_device_manifest")
      |> maybe_add_failure(
        device_manifest_present == true and device_manifest_ready == false,
        "device_manifest_not_ready"
      )
      |> maybe_add_failure(
        cuda_visible_devices_present == false,
        "missing_cuda_visible_devices"
      )
      |> maybe_add_failure(
        cuda_visible_devices_present == true and cuda_visible_devices_ready == false,
        "cuda_visible_devices_not_ready"
      )

    probe_failure_count = length(host_probe_failures)

    probe_required_resources =
      required_resources(vendor_socket_path, device_manifest_path, cuda_visible_devices)

    handshake_target =
      handshake_target(vendor_surface, execution_lane, vendor_socket_path, device_manifest_path)

    host_probe_mode =
      cond do
        strict_host_probe -> "strict_host_checks"
        vendor_socket_path || device_manifest_path || cuda_visible_devices -> "host_checks"
        true -> "clean_room"
      end

    host_probe_status =
      cond do
        probe_failure_count == 0 -> "ready"
        strict_host_probe -> "blocked"
        true -> "degraded"
      end

    handshake_state = if host_probe_status == "blocked", do: "blocked", else: "pending"

    state
    |> Map.put(:handshake_ref, "aerial://#{vendor_surface}/#{execution_lane}/handshake")
    |> Map.put(:handshake_state, handshake_state)
    |> Map.put(:handshake_attempts, state.handshake_attempts + 1)
    |> Map.put(:last_handshake_at, now)
    |> Map.put(:strict_host_probe, strict_host_probe)
    |> Map.put(:activation_gate, activation_gate)
    |> Map.put(:handshake_target, handshake_target)
    |> Map.put(:probe_evidence_ref, "probe-evidence://aerial/#{vendor_surface}/#{execution_lane}")
    |> Map.put(:probe_checked_at, now)
    |> Map.put(:probe_required_resources, probe_required_resources)
    |> Map.put(:probe_observations, probe_observations)
    |> Map.put(:host_probe_ref, "probe://aerial/#{vendor_surface}/#{execution_lane}")
    |> Map.put(:host_probe_status, host_probe_status)
    |> Map.put(:host_probe_mode, host_probe_mode)
    |> Map.put(:host_probe_failures, host_probe_failures)
    |> Map.put(:vendor_socket_path, vendor_socket_path)
    |> Map.put(:vendor_socket_present, vendor_socket_present)
    |> Map.put(:vendor_socket_usable, vendor_socket_usable)
    |> Map.put(:device_manifest_path, device_manifest_path)
    |> Map.put(:device_manifest_present, device_manifest_present)
    |> Map.put(:device_manifest_ready, device_manifest_ready)
    |> Map.put(:cuda_visible_devices, cuda_visible_devices)
    |> Map.put(:cuda_visible_devices_present, cuda_visible_devices_present)
    |> Map.put(:cuda_visible_devices_ready, cuda_visible_devices_ready)
    |> Map.put(:probe_failure_count, probe_failure_count)
  end

  def activate_cell(state) do
    case strict_probe_blocked?(state) do
      true -> {:error, :host_probe_failed}
      false -> {:ok, Map.put(state, :handshake_state, "ready")}
    end
  end

  def quiesce(state) do
    Map.put(state, :handshake_state, "draining")
  end

  def resume(state) do
    case strict_probe_blocked?(state) do
      true ->
        {:error, :host_probe_failed}

      false ->
        {:ok,
         state
         |> Map.put(:handshake_state, "ready")
         |> Map.put(:last_handshake_at, now_iso8601())
         |> Map.put(:probe_checked_at, now_iso8601())}
    end
  end

  def terminate(state) do
    state
    |> Map.put(:handshake_state, "terminated")
    |> Map.put(:host_probe_status, "released")
  end

  def health_checks(state) do
    %{
      handshake_ref: state.handshake_ref,
      handshake_state: state.handshake_state,
      handshake_attempts: state.handshake_attempts,
      last_handshake_at: state.last_handshake_at,
      strict_host_probe: state.strict_host_probe,
      activation_gate: state.activation_gate,
      handshake_target: state.handshake_target,
      probe_evidence_ref: state.probe_evidence_ref,
      probe_checked_at: state.probe_checked_at,
      probe_required_resources: state.probe_required_resources,
      probe_observations: state.probe_observations,
      host_probe_ref: state.host_probe_ref,
      host_probe_status: state.host_probe_status,
      host_probe_mode: state.host_probe_mode,
      host_probe_failures: state.host_probe_failures,
      vendor_socket_path: state.vendor_socket_path,
      vendor_socket_present: state.vendor_socket_present,
      vendor_socket_usable: state.vendor_socket_usable,
      device_manifest_path: state.device_manifest_path,
      device_manifest_present: state.device_manifest_present,
      device_manifest_ready: state.device_manifest_ready,
      cuda_visible_devices: state.cuda_visible_devices,
      cuda_visible_devices_present: state.cuda_visible_devices_present,
      cuda_visible_devices_ready: state.cuda_visible_devices_ready,
      probe_failure_count: state.probe_failure_count
    }
  end

  defp optional_path_present(nil), do: nil
  defp optional_path_present(""), do: nil
  defp optional_path_present(path), do: File.exists?(path)

  defp env_value_present?(nil), do: nil
  defp env_value_present?(""), do: false
  defp env_value_present?(value), do: String.trim(to_string(value)) != ""

  defp probe_observations(
         vendor_socket_observations,
         device_manifest_observations,
         cuda_observations
       ) do
    %{}
    |> maybe_put_observation("vendor_socket", vendor_socket_observations)
    |> maybe_put_observation("device_manifest", device_manifest_observations)
    |> maybe_put_observation("cuda_visible_devices", cuda_observations)
  end

  defp required_resources(vendor_socket_path, device_manifest_path, cuda_visible_devices) do
    []
    |> maybe_add_resource(present?(vendor_socket_path), "path:#{vendor_socket_path}")
    |> maybe_add_resource(present?(device_manifest_path), "path:#{device_manifest_path}")
    |> maybe_add_resource(
      present?(cuda_visible_devices),
      "env:CUDA_VISIBLE_DEVICES=#{cuda_visible_devices}"
    )
    |> case do
      [] -> ["clean_room"]
      resources -> resources
    end
  end

  defp handshake_target(vendor_surface, execution_lane, vendor_socket_path, device_manifest_path) do
    target =
      cond do
        present?(vendor_socket_path) -> "path:#{vendor_socket_path}"
        present?(device_manifest_path) -> "path:#{device_manifest_path}"
        true -> "clean_room"
      end

    "surface:#{vendor_surface || "opaque"} lane:#{execution_lane || "gpu_batch"} -> #{target}"
  end

  defp strict_probe_blocked?(state) do
    state.strict_host_probe and state.host_probe_status != "ready"
  end

  defp maybe_add_failure(failures, true, failure), do: failures ++ [failure]
  defp maybe_add_failure(failures, false, _failure), do: failures
  defp maybe_add_resource(resources, true, resource), do: resources ++ [resource]
  defp maybe_add_resource(resources, false, _resource), do: resources
  defp maybe_put_observation(observations, _key, nil), do: observations

  defp maybe_put_observation(observations, _key, value)
       when is_map(value) and map_size(value) == 0,
       do: observations

  defp maybe_put_observation(observations, key, value), do: Map.put(observations, key, value)
  defp present?(value), do: value not in [nil, ""]

  defp path_usable?(nil), do: nil

  defp path_usable?(observations) when is_map(observations) do
    kind = Map.get(observations, "kind")
    open_status = Map.get(observations, "open_status")
    kind == "regular" and open_status == "ok"
  end

  defp manifest_ready?(nil), do: nil

  defp manifest_ready?(observations) when is_map(observations) do
    Map.get(observations, "bytes", 0) > 0 and Map.get(observations, "read_status") == "ok"
  end

  defp cuda_ready?(nil), do: nil

  defp cuda_ready?(observations) when is_map(observations),
    do: Map.get(observations, "count", 0) > 0

  defp path_observations(nil), do: nil
  defp path_observations(""), do: nil

  defp path_observations(path) do
    case File.stat(path) do
      {:ok, stat} ->
        %{
          "kind" => atom_or_value(stat.type),
          "size" => stat.size,
          "mode" => Integer.to_string(stat.mode, 8),
          "open_status" => open_status(path, stat.type)
        }

      {:error, _reason} ->
        nil
    end
  end

  defp manifest_observations(nil), do: nil
  defp manifest_observations(""), do: nil

  defp manifest_observations(path) do
    case File.read(path) do
      {:ok, contents} ->
        kv_pairs = parse_kv_lines(contents)
        trimmed = String.trim(contents)

        %{
          "format" =>
            cond do
              kv_pairs != [] -> "kv"
              trimmed == "" -> "empty"
              String.starts_with?(trimmed, "{") -> "jsonish"
              true -> "raw"
            end,
          "entry_count" => length(kv_pairs),
          "entry_keys" => Enum.map(kv_pairs, &elem(&1, 0)),
          "bytes" => byte_size(contents),
          "read_status" => "ok"
        }
        |> compact_map()

      {:error, _reason} ->
        nil
    end
  end

  defp cuda_observations(nil), do: nil
  defp cuda_observations(""), do: %{"raw" => "", "count" => 0}

  defp cuda_observations(value) do
    devices =
      value
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{
      "raw" => to_string(value),
      "count" => length(devices),
      "devices" => devices
    }
  end

  defp open_status(path, :regular) do
    case :file.open(String.to_charlist(path), [:read, :raw]) do
      {:ok, io} ->
        :ok = :file.close(io)
        "ok"

      {:error, reason} ->
        atom_or_value(reason)
    end
  end

  defp open_status(_path, type), do: "skipped:#{atom_or_value(type)}"

  defp truthy?(value) when value in [true, "true", "1", 1, true], do: true
  defp truthy?(_value), do: false

  defp parse_kv_lines(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.flat_map(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] when key != "" and value != "" -> [{String.trim(key), String.trim(value)}]
        _ -> []
      end
    end)
  end

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" or value == [] end)
    |> Enum.into(%{})
  end

  defp atom_or_value(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_or_value(value), do: value

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
