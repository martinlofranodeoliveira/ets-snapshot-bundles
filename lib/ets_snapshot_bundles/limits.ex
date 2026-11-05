defmodule EtsSnapshotBundles.Limits do
  @moduledoc false
  @defaults %{max_keys: 4096, max_payload_bytes: 1_048_576, max_leases: 128, retired_limit: 2}
  @ceilings %{
    max_keys: 65_536,
    max_payload_bytes: 16_777_216,
    max_leases: 4096,
    retired_limit: 16
  }

  def new(options) when is_map(options) and map_size(options) <= 4 do
    valid =
      Enum.all?(options, fn {key, value} ->
        case Map.fetch(@ceilings, key) do
          {:ok, ceiling} ->
            minimum = if key == :max_leases, do: 1, else: 0
            is_integer(value) and value >= minimum and value <= ceiling

          :error ->
            false
        end
      end)

    if valid, do: {:ok, Map.merge(@defaults, options)}, else: {:error, :invalid_options}
  end

  def new(_), do: {:error, :invalid_options}

  def request(options, publication?) when is_map(options) and map_size(options) <= 2 do
    allowed = if publication?, do: [:timeout, :expected_generation], else: [:timeout]
    timeout = Map.get(options, :timeout, 5000)
    expected = Map.get(options, :expected_generation)

    if Enum.all?(Map.keys(options), &(&1 in allowed)) and
         is_integer(timeout) and timeout >= 0 and timeout <= 60_000 and
         (is_nil(expected) or (is_integer(expected) and expected >= 0)) do
      {:ok, timeout, expected}
    else
      {:error, :invalid_options}
    end
  end

  def request(_, _), do: {:error, :invalid_options}
end
