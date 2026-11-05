defmodule EtsSnapshotBundles.CoherenceTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "a lease sees one complete generation across several publications" do
    index = index()
    assert {:ok, 1} = B.publish(index, [{"a", "old-a"}, {"b", "old-b"}])
    assert {:ok, first} = B.acquire(index)
    assert {:ok, 2} = B.publish(index, [{"a", "new-a"}, {"b", "new-b"}])
    assert {:ok, second} = B.acquire(index)
    assert B.lookup(first, "a") == {:ok, "old-a"}
    assert B.lookup(first, "b") == {:ok, "old-b"}
    assert B.lookup(second, "a") == {:ok, "new-a"}
    assert B.lookup(second, "b") == {:ok, "new-b"}
    assert B.lookup(first, "missing") == :not_found
    assert :ok = B.release(first)
    assert :ok = B.release(second)
    assert stats(index).table_count == 1
  end

  test "generation zero and complete replacement, including empty publication" do
    index = index()
    assert stats(index).generation == 0
    {:ok, empty} = B.acquire(index)
    assert B.lookup(empty, "a") == :not_found
    assert {:ok, 1} = B.publish(index, [{"a", "value"}])
    assert B.lookup(empty, "a") == :not_found
    assert :ok = B.release(empty)
    assert {:ok, 2} = B.publish(index, [])
    {:ok, lease} = B.acquire(index)
    assert B.lookup(lease, "a") == :not_found
    assert stats(index).current_payload_bytes == 0
    assert :ok = B.release(lease)
  end

  test "compare-and-publish rejects without advancing or reclaiming" do
    index = index()
    assert {:ok, 1} = B.publish(index, [{"a", "one"}])
    assert {:ok, 2} = B.publish(index, [{"a", "two"}], %{expected_generation: 1})
    before = stats(index)

    assert B.publish(index, [{"a", "wrong"}], %{expected_generation: 1}) ==
             {:error, :stale_generation}

    assert stats(index) == before
    {:ok, lease} = B.acquire(index)
    assert B.lookup(lease, "a") == {:ok, "two"}
    assert :ok = B.release(lease)
  end
end
