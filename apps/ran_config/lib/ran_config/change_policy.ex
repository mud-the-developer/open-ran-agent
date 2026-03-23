defmodule RanConfig.ChangePolicy do
  @moduledoc """
  Controlled failover policy helpers for backend switch planning.
  """

  @spec switch_policy(String.t(), atom() | nil) :: {:ok, map()} | {:error, map()}
  def switch_policy(cell_group_id, target_backend \\ nil) do
    with {:ok, cell_group} <- RanConfig.find_cell_group(cell_group_id) do
      current_backend = cell_group[:backend] || cell_group["backend"]

      allowed_targets =
        [current_backend | cell_group[:failover_targets] || cell_group["failover_targets"] || []]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      policy = %{
        cell_group: cell_group_id,
        current_backend: current_backend,
        rollback_target: current_backend,
        allowed_targets: allowed_targets,
        target_backend: target_backend
      }

      cond do
        is_nil(target_backend) ->
          {:ok, Map.put(policy, :target_preprovisioned, true)}

        target_backend in allowed_targets ->
          {:ok, Map.put(policy, :target_preprovisioned, true)}

        true ->
          {:error,
           %{
             status: "policy_denied",
             command: "plan",
             errors: [
               %{
                 field: "target_backend",
                 message: "#{target_backend} is not pre-provisioned for #{cell_group_id}",
                 allowed_targets: Enum.map(allowed_targets, &Atom.to_string/1)
               }
             ],
             policy: format_policy(policy, false)
           }}
      end
    else
      {:error, :not_found} ->
        {:error,
         %{
           status: "policy_denied",
           command: "plan",
           errors: [%{field: "cell_group", message: "#{cell_group_id} is not defined"}]
         }}
    end
  end

  defp format_policy(policy, allowed?) do
    %{
      cell_group: policy.cell_group,
      current_backend: Atom.to_string(policy.current_backend),
      rollback_target: Atom.to_string(policy.rollback_target),
      allowed_targets: Enum.map(policy.allowed_targets, &Atom.to_string/1),
      target_backend: maybe_to_string(policy.target_backend),
      target_preprovisioned: allowed?
    }
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value), do: value
end
