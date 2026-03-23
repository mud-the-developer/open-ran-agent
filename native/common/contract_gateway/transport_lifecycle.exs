defmodule NativeContractGateway.TransportLifecycle do
  def new(overrides \\ %{}) do
    overrides = normalize_attrs(overrides)

    defaults = %{
      session_epoch: nil,
      session_started_at: nil,
      last_submit_at: nil,
      last_submit_batch_size: 0,
      last_submit_cost_us: 0,
      last_uplink_at: nil,
      last_resume_at: nil,
      last_quiesce_at: nil,
      drain_reason: "none",
      deadline_miss_count: 0,
      timing_window_us: 0,
      transport_queue_depth: 0
    }

    Map.merge(defaults, overrides)
  end

  def open_session(state, attrs \\ %{}) do
    attrs = normalize_attrs(attrs)
    now = now_iso8601()

    state
    |> Map.merge(%{
      session_epoch: System.system_time(:microsecond),
      session_started_at: now,
      last_resume_at: now,
      last_quiesce_at: nil,
      drain_reason: "none"
    })
    |> Map.merge(attrs)
  end

  def submit(state, attrs \\ %{}) do
    attrs = normalize_attrs(attrs)
    batch_size = Map.get(attrs, :batch_size, 0)
    timing_window_us = Map.get(attrs, :timing_window_us, Map.get(state, :timing_window_us, 0))
    submit_cost_us = submit_cost_us(attrs, batch_size)

    deadline_miss_count =
      if timing_window_us > 0 and submit_cost_us > timing_window_us do
        Map.get(state, :deadline_miss_count, 0) + 1
      else
        Map.get(state, :deadline_miss_count, 0)
      end

    state
    |> Map.merge(%{
      last_submit_at: now_iso8601(),
      last_submit_batch_size: batch_size,
      last_submit_cost_us: submit_cost_us,
      deadline_miss_count: deadline_miss_count,
      timing_window_us: timing_window_us,
      transport_queue_depth:
        normalize_non_neg(
          Map.get(attrs, :transport_queue_depth, Map.get(state, :transport_queue_depth, 0))
        )
    })
  end

  def uplink(state, attrs \\ %{}) do
    attrs = normalize_attrs(attrs)

    state
    |> Map.merge(%{
      last_uplink_at: now_iso8601(),
      transport_queue_depth:
        normalize_non_neg(
          Map.get(attrs, :transport_queue_depth, Map.get(state, :transport_queue_depth, 0))
        )
    })
  end

  def quiesce(state, reason) do
    Map.merge(state, %{
      drain_reason: reason || "quiesce",
      last_quiesce_at: now_iso8601()
    })
  end

  def resume(state, attrs \\ %{}) do
    attrs = normalize_attrs(attrs)

    state
    |> Map.merge(%{
      drain_reason: "none",
      last_resume_at: now_iso8601(),
      last_quiesce_at: nil,
      transport_queue_depth:
        normalize_non_neg(
          Map.get(attrs, :transport_queue_depth, Map.get(state, :transport_queue_depth, 0))
        )
    })
    |> Map.merge(attrs)
  end

  def health_checks(state) do
    %{
      session_epoch: state.session_epoch,
      session_started_at: state.session_started_at,
      last_submit_at: state.last_submit_at,
      last_submit_batch_size: state.last_submit_batch_size,
      last_submit_cost_us: state.last_submit_cost_us,
      last_uplink_at: state.last_uplink_at,
      last_resume_at: state.last_resume_at,
      last_quiesce_at: state.last_quiesce_at,
      drain_reason: state.drain_reason,
      deadline_miss_count: state.deadline_miss_count,
      transport_queue_depth: state.transport_queue_depth,
      timing_window_us: state.timing_window_us
    }
  end

  defp submit_cost_us(attrs, batch_size) do
    cond do
      is_integer(Map.get(attrs, :submit_cost_us)) ->
        Map.get(attrs, :submit_cost_us)

      true ->
        max(batch_size, 1) * Map.get(attrs, :unit_cost_us, 100)
    end
  end

  defp normalize_non_neg(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg(_value), do: 0

  defp normalize_attrs(attrs) when is_list(attrs), do: Enum.into(attrs, %{})
  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(_attrs), do: %{}

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
