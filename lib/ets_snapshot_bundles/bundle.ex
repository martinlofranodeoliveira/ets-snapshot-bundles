defmodule EtsSnapshotBundles.Bundle do
  @moduledoc false

  def key?(key), do: is_binary(key) and byte_size(key) <= 128

  # Inspect at most max_keys + 1 list cells, without invoking Enumerable.
  def prepare(entries, limits) do
    with {:ok, reversed, count, bytes} <- scan(entries, limits, [], 0, 0),
         :ok <- unique(reversed) do
      {:ok, Enum.reverse(reversed), count, bytes}
    end
  end

  defp scan([], _limits, acc, count, bytes), do: {:ok, acc, count, bytes}

  defp scan([_ | _], %{max_keys: maximum}, _acc, count, _bytes) when count >= maximum,
    do: {:error, :too_many_keys}

  defp scan([{key, value} = entry | rest], limits, acc, count, bytes)
       when is_binary(key) and is_binary(value) do
    cond do
      byte_size(key) > 128 ->
        {:error, :key_too_large}

      byte_size(value) > 4096 ->
        {:error, :value_too_large}

      bytes + byte_size(key) + byte_size(value) > limits.max_payload_bytes ->
        {:error, :payload_limit}

      true ->
        scan(rest, limits, [entry | acc], count + 1, bytes + byte_size(key) + byte_size(value))
    end
  end

  defp scan([_ | _], _limits, _acc, _count, _bytes), do: {:error, :invalid_entry}
  defp scan(_, _limits, _acc, _count, _bytes), do: {:error, :invalid_entries}

  defp unique(entries) do
    Enum.reduce_while(entries, MapSet.new(), fn {key, _}, seen ->
      if MapSet.member?(seen, key) do
        {:halt, {:error, :duplicate_key}}
      else
        {:cont, MapSet.put(seen, key)}
      end
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  def build(entries) do
    try do
      table = :ets.new(__MODULE__, [:set, :protected, read_concurrency: true])

      try do
        true = :ets.insert(table, entries)
        {:ok, table}
      catch
        :error, :system_limit ->
          :ets.delete(table)
          {:error, :resource_limit}

        kind, reason ->
          :ets.delete(table)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    catch
      :error, :system_limit -> {:error, :resource_limit}
    end
  end
end
