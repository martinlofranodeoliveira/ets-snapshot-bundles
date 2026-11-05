defmodule EtsSnapshotBundles.ValidationTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "duplicate rejection preserves tables, payload, generation and values" do
    index = index()
    assert {:ok, 1} = B.publish(index, [{"a", "kept"}, {"b", "also-kept"}])
    {:ok, lease} = B.acquire(index)
    before = stats(index)
    tables = owned_tables(index)
    assert B.publish(index, [{"a", "x"}, {"a", "y"}]) == {:error, :duplicate_key}
    assert stats(index) == before
    assert owned_tables(index) == tables
    assert B.lookup(lease, "a") == {:ok, "kept"}
    assert B.lookup(lease, "b") == {:ok, "also-kept"}
    assert :ok = B.release(lease)
  end

  test "byte boundaries, empty binaries and logical payload" do
    index = index(%{max_payload_bytes: 5000})
    key = :binary.copy(<<255>>, 128)
    value = :binary.copy(<<0>>, 4096)
    assert {:ok, 1} = B.publish(index, [{key, value}, {"", ""}])
    assert stats(index).current_payload_bytes == 4224
    assert B.publish(index, [{key <> "x", ""}]) == {:error, :key_too_large}
    assert B.publish(index, [{"a", value <> "x"}]) == {:error, :value_too_large}
    {:ok, lease} = B.acquire(index)
    assert B.lookup(lease, key) == {:ok, value}
    assert B.lookup(lease, "") == {:ok, ""}
    assert B.lookup(lease, key <> "x") == {:error, :invalid_key}
    assert :ok = B.release(lease)
  end

  test "only a bounded proper list is ingested, never Enumerable" do
    index = index(%{max_keys: 2, max_payload_bytes: 4})
    stream = Stream.repeatedly(fn -> raise "must not enumerate" end)
    assert B.publish(index, stream) == {:error, :invalid_entries}
    assert B.publish(index, %{"a" => "b"}) == {:error, :invalid_entries}
    assert B.publish(index, [{"a", "b"} | :tail]) == {:error, :invalid_entries}
    assert B.publish(index, [{:a, "b"}]) == {:error, :invalid_entry}
    assert B.publish(index, [{"a", "bb"}, {"c", "d"}]) == {:error, :payload_limit}
    assert B.publish(index, [{"", ""}, {"a", ""}, :invalid]) == {:error, :too_many_keys}
    assert stats(index).generation == 0
    assert stats(index).table_count == 1
    assert :atomics.get(index.gate, 1) == 0
  end
end
