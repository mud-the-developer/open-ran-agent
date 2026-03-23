defmodule LocalDuLowAdapter.TransportProbe do
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
      host_probe_mode: "loopback",
      host_probe_failures: [],
      host_interface: nil,
      host_interface_present: nil,
      host_interface_ready: nil,
      device_path: nil,
      device_path_present: nil,
      device_path_usable: nil,
      pci_bdf: nil,
      pci_bdf_present: nil,
      pci_bdf_ready: nil,
      probe_failure_count: 0
    }
  end

  def open_session(state) do
    fronthaul_session = state.fronthaul_session || "local_du_low_port"
    session_payload = state.session_payload || %{}
    now = now_iso8601()
    host_interface = Map.get(session_payload, "host_interface", "lo")
    device_path = Map.get(session_payload, "device_path")
    pci_bdf = Map.get(session_payload, "pci_bdf")

    host_interface_present = interface_present?(host_interface)
    device_path_present = optional_path_present(device_path)
    pci_bdf_present = optional_pci_present(pci_bdf)
    host_interface_observations = interface_observations(host_interface)
    device_path_observations = path_observations(device_path)
    pci_bdf_observations = pci_observations(pci_bdf)
    host_interface_ready = interface_ready?(host_interface_observations)
    device_path_usable = path_usable?(device_path_observations)
    pci_bdf_ready = pci_ready?(pci_bdf_observations)
    strict_host_probe = truthy?(Map.get(session_payload, "strict_host_probe"))
    activation_gate = if strict_host_probe, do: "strict", else: "warn_only"

    probe_observations =
      probe_observations(
        host_interface_observations,
        device_path_observations,
        pci_bdf_observations
      )

    host_probe_failures =
      []
      |> maybe_add_failure(host_interface_present == false, "missing_host_interface")
      |> maybe_add_failure(
        host_interface_present == true and host_interface_ready == false,
        "host_interface_unready"
      )
      |> maybe_add_failure(device_path_present == false, "missing_device_path")
      |> maybe_add_failure(
        device_path_present == true and device_path_usable == false,
        "device_path_not_usable"
      )
      |> maybe_add_failure(pci_bdf_present == false, "missing_pci_bdf")
      |> maybe_add_failure(
        pci_bdf_present == true and pci_bdf_ready == false,
        "pci_probe_incomplete"
      )

    probe_failure_count = length(host_probe_failures)
    probe_required_resources = required_resources(host_interface, device_path, pci_bdf)
    handshake_target = handshake_target(host_interface, device_path, pci_bdf)

    host_probe_mode =
      cond do
        strict_host_probe -> "strict_host_checks"
        device_path || pci_bdf || host_interface != "lo" -> "host_checks"
        true -> "loopback"
      end

    host_probe_status =
      cond do
        probe_failure_count == 0 -> "ready"
        strict_host_probe -> "blocked"
        true -> "degraded"
      end

    handshake_state = if host_probe_status == "blocked", do: "blocked", else: "pending"

    state
    |> Map.put(:handshake_ref, "local_du_low://#{fronthaul_session}/handshake")
    |> Map.put(:handshake_state, handshake_state)
    |> Map.put(:handshake_attempts, state.handshake_attempts + 1)
    |> Map.put(:last_handshake_at, now)
    |> Map.put(:strict_host_probe, strict_host_probe)
    |> Map.put(:activation_gate, activation_gate)
    |> Map.put(:handshake_target, handshake_target)
    |> Map.put(:probe_evidence_ref, "probe-evidence://local_du_low/#{fronthaul_session}")
    |> Map.put(:probe_checked_at, now)
    |> Map.put(:probe_required_resources, probe_required_resources)
    |> Map.put(:probe_observations, probe_observations)
    |> Map.put(:host_probe_ref, "probe://local_du_low/#{fronthaul_session}")
    |> Map.put(:host_probe_status, host_probe_status)
    |> Map.put(:host_probe_mode, host_probe_mode)
    |> Map.put(:host_probe_failures, host_probe_failures)
    |> Map.put(:host_interface, host_interface)
    |> Map.put(:host_interface_present, host_interface_present)
    |> Map.put(:host_interface_ready, host_interface_ready)
    |> Map.put(:device_path, device_path)
    |> Map.put(:device_path_present, device_path_present)
    |> Map.put(:device_path_usable, device_path_usable)
    |> Map.put(:pci_bdf, pci_bdf)
    |> Map.put(:pci_bdf_present, pci_bdf_present)
    |> Map.put(:pci_bdf_ready, pci_bdf_ready)
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
      host_interface: state.host_interface,
      host_interface_present: state.host_interface_present,
      host_interface_ready: state.host_interface_ready,
      device_path: state.device_path,
      device_path_present: state.device_path_present,
      device_path_usable: state.device_path_usable,
      pci_bdf: state.pci_bdf,
      pci_bdf_present: state.pci_bdf_present,
      pci_bdf_ready: state.pci_bdf_ready,
      probe_failure_count: state.probe_failure_count
    }
  end

  defp interface_present?(nil), do: nil
  defp interface_present?(""), do: nil
  defp interface_present?(name), do: File.exists?("/sys/class/net/#{name}")

  defp optional_path_present(nil), do: nil
  defp optional_path_present(""), do: nil
  defp optional_path_present(path), do: File.exists?(path)

  defp optional_pci_present(nil), do: nil
  defp optional_pci_present(""), do: nil
  defp optional_pci_present(bdf), do: File.exists?("/sys/bus/pci/devices/#{bdf}")

  defp probe_observations(
         host_interface_observations,
         device_path_observations,
         pci_bdf_observations
       ) do
    %{}
    |> maybe_put_observation("host_interface", host_interface_observations)
    |> maybe_put_observation("device_path", device_path_observations)
    |> maybe_put_observation("pci_bdf", pci_bdf_observations)
  end

  defp required_resources(host_interface, device_path, pci_bdf) do
    []
    |> maybe_add_resource(present?(host_interface), "netif:#{host_interface}")
    |> maybe_add_resource(present?(device_path), "path:#{device_path}")
    |> maybe_add_resource(present?(pci_bdf), "pci:#{pci_bdf}")
    |> case do
      [] -> ["loopback"]
      resources -> resources
    end
  end

  defp handshake_target(host_interface, device_path, pci_bdf) do
    left =
      case host_interface do
        value when value in [nil, ""] -> "loopback"
        value -> "netif:#{value}"
      end

    right =
      cond do
        present?(device_path) -> "path:#{device_path}"
        present?(pci_bdf) -> "pci:#{pci_bdf}"
        true -> "loopback"
      end

    "#{left} -> #{right}"
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

  defp interface_ready?(nil), do: nil

  defp interface_ready?(observations) when is_map(observations),
    do: Map.get(observations, "ready")

  defp path_usable?(nil), do: nil

  defp path_usable?(observations) when is_map(observations) do
    kind = Map.get(observations, "kind")
    open_status = Map.get(observations, "open_status")
    kind in ["regular", "device"] and open_status == "ok"
  end

  defp pci_ready?(nil), do: nil
  defp pci_ready?(observations) when is_map(observations), do: Map.get(observations, "ready")

  defp interface_ready(path) do
    operstate = read_trimmed(Path.join(path, "operstate"))
    carrier = read_trimmed(Path.join(path, "carrier"))
    operstate in ["up", "unknown"] and carrier != "0"
  end

  defp pci_ready(path) do
    Enum.all?(
      [Path.join(path, "vendor"), Path.join(path, "device"), Path.join(path, "class")],
      fn file -> read_trimmed(file) not in [nil, ""] end
    )
  end

  defp open_status(path, type) when type in [:regular, :device] do
    case :file.open(String.to_charlist(path), [:read, :raw]) do
      {:ok, io} ->
        :ok = :file.close(io)
        "ok"

      {:error, reason} ->
        atom_or_nil(reason)
    end
  end

  defp open_status(_path, type), do: "skipped:#{atom_or_nil(type)}"

  defp interface_observations(nil), do: nil
  defp interface_observations(""), do: nil

  defp interface_observations(name) do
    path = "/sys/class/net/#{name}"

    %{
      "sysfs_path" => path,
      "operstate" => read_trimmed(Path.join(path, "operstate")),
      "mtu" => read_trimmed(Path.join(path, "mtu")),
      "carrier" => read_trimmed(Path.join(path, "carrier")),
      "address" => read_trimmed(Path.join(path, "address")),
      "ready" => interface_ready(path)
    }
    |> compact_map()
  end

  defp path_observations(nil), do: nil
  defp path_observations(""), do: nil

  defp path_observations(path) do
    case File.stat(path) do
      {:ok, stat} ->
        %{
          "kind" => atom_or_nil(stat.type),
          "size" => stat.size,
          "mode" => Integer.to_string(stat.mode, 8),
          "open_status" => open_status(path, stat.type)
        }

      {:error, _reason} ->
        nil
    end
  end

  defp pci_observations(nil), do: nil
  defp pci_observations(""), do: nil

  defp pci_observations(bdf) do
    path = "/sys/bus/pci/devices/#{bdf}"

    %{
      "sysfs_path" => path,
      "vendor" => read_trimmed(Path.join(path, "vendor")),
      "device" => read_trimmed(Path.join(path, "device")),
      "class" => read_trimmed(Path.join(path, "class")),
      "ready" => pci_ready(path)
    }
    |> compact_map()
  end

  defp truthy?(value) when value in [true, "true", "1", 1, true], do: true
  defp truthy?(_value), do: false

  defp read_trimmed(path) do
    case File.read(path) do
      {:ok, contents} -> String.trim(contents)
      {:error, _reason} -> nil
    end
  end

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.into(%{})
  end

  defp atom_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_or_nil(value), do: value

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
