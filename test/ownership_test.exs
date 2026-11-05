defmodule EtsSnapshotBundles.OwnershipTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "leases bind to the server instance PID and acquiring caller PID" do
    index = index()
    assert index.pid != self()
    assert {:ok, 1} = B.publish(index, [{"a", "old"}])
    {:ok, lease} = B.acquire(index)
    assert lease.index == index
    assert lease.index.pid == index.pid
    assert lease.owner == self()
    assert lease.generation == 1
    other = reader()
    assert ask(other, fn -> B.lookup(lease, "a") end) == {:error, :not_owner}
    assert ask(other, fn -> B.release(lease) end) == {:error, :not_owner}
    assert {:ok, 2} = B.publish(index, [{"a", "new"}])
    assert B.lookup(lease, "a") == {:ok, "old"}
    assert :ok = B.release(lease)
    assert :ok = B.release(lease)
    assert B.lookup(lease, "a") == {:error, :stale_snapshot}
    assert ask(other, fn -> B.lookup(lease, "a") end) == {:error, :not_owner}
    assert ask(other, fn -> B.release(lease) end) == {:error, :not_owner}
    assert stats(index).leases == 0
    assert stats(index).lease_monitors == 0
  end

  test "lease limit rejection leaves the existing pin unchanged" do
    index = index(%{max_leases: 1})
    {:ok, lease} = B.acquire(index)
    before = stats(index)
    assert B.acquire(index) == {:error, :lease_limit}
    assert stats(index) == before
    assert :ok = B.release(lease)
    assert {:ok, another} = B.acquire(index)
    assert :ok = B.release(another)
  end
end
