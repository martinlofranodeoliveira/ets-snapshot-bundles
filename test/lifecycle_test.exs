defmodule EtsSnapshotBundles.LifecycleTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "owner death destroys tables and old handles cannot reach a new instance" do
    old = index()
    assert {:ok, 1} = B.publish(old, [{"a", "old"}])
    {:ok, lease} = B.acquire(old)
    tables = owned_tables(old)
    monitor = Process.monitor(old.pid)
    Process.exit(old.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
    for table <- tables, do: assert(:ets.info(table) == :undefined)
    assert B.lookup(lease, "a") == {:error, :unavailable}
    assert B.release(lease) == {:error, :unavailable}
    assert B.inspect(old) == {:error, :unavailable}

    fresh = index()
    assert fresh.instance != old.instance
    assert stats(fresh).generation == 0
    assert stats(fresh).current_keys == 0
    {:ok, empty} = B.acquire(fresh)
    assert B.lookup(empty, "a") == :not_found
    # Even a handle incorrectly pointed at the new PID retains its old token.
    forged = %{lease | index: %{fresh | instance: old.instance}}
    assert B.lookup(forged, "a") == {:error, :unavailable}
    assert :ok = B.release(empty)
  end

  test "owner death releases queued slots without waiting for a deadline" do
    index = index()
    :ok = :sys.suspend(index.pid)
    call = probed(fn -> B.acquire(index, %{timeout: 60_000}) end)
    event(call, :dispatched)
    monitor = Process.monitor(index.pid)
    Process.exit(index.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
    assert result(call) == {:error, :unavailable}
    event(call, :freed)
    assert :atomics.get(index.gate, 1) == 0
  end

  test "owner death before dispatch and close both invalidate the exact instance" do
    index = index()
    call = probed(fn -> B.inspect(index, %{timeout: 60_000}) end, :before_dispatch)
    event(call, :before_dispatch)
    Process.exit(index.pid, :kill)
    assert result(call) == {:error, :unavailable}
    event(call, :freed)
    fresh = index()
    {:ok, lease} = B.acquire(fresh)
    tables = owned_tables(fresh)
    assert :ok = B.close(fresh)
    refute Process.alive?(fresh.pid)
    for table <- tables, do: assert(:ets.info(table) == :undefined)
    assert B.lookup(lease, "x") == {:error, :unavailable}
  end
end
