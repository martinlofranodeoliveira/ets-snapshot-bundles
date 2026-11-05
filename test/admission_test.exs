defmodule EtsSnapshotBundles.AdmissionTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "64 queued requests hold all slots even after their callers time out" do
    index = index()
    :ok = :sys.suspend(index.pid)

    calls =
      for _ <- 1..64 do
        call = probed(fn -> B.inspect(index, %{timeout: 60_000}) end)
        worker = event(call, :dispatched)
        {call, worker}
      end

    assert :atomics.get(index.gate, 1) == 64
    assert B.acquire(index) == {:error, :busy}
    assert B.publish(index, []) == {:error, :busy}
    assert B.inspect(index) == {:error, :busy}

    for {call, worker} <- calls do
      expire(worker, call)
      event(call, :cancelled)
      assert result(call) == {:error, :timeout}
      dead(call)
    end

    assert :atomics.get(index.gate, 1) == 64
    {:messages, messages} = Process.info(index.pid, :messages)
    assert Enum.count(messages, &match?({:bundle_request, _, _, _, _, _, _}, &1)) == 64
    :ok = :sys.resume(index.pid)
    for {call, _} <- calls, do: event(call, :freed)
    assert :atomics.get(index.gate, 1) == 0
    assert stats(index).leases == 0
    assert stats(index).table_count == 1
  end

  test "death before dispatch returns a claimed slot without sending owner work" do
    index = index()
    call = probed(fn -> B.acquire(index, %{timeout: 60_000}) end, :before_dispatch)
    event(call, :before_dispatch)
    assert :atomics.get(index.gate, 1) == 1
    Process.exit(call.caller, :kill)
    dead(call)
    event(call, :freed)
    assert :atomics.get(index.gate, 1) == 0
    assert stats(index).leases == 0
    refute_receive {:probe, _, :dispatched, _}, 0
  end

  test "a dead queued caller is cancelled before its acquire can allocate a pin" do
    index = index()
    :ok = :sys.suspend(index.pid)
    call = probed(fn -> B.acquire(index, %{timeout: 60_000}) end)
    event(call, :dispatched)
    Process.exit(call.caller, :kill)
    dead(call)
    event(call, :cancelled)
    assert :atomics.get(index.gate, 1) == 1
    :ok = :sys.resume(index.pid)
    event(call, :freed)
    assert stats(index).leases == 0
    assert stats(index).lease_monitors == 0
  end

  test "every lease operation uses admission, including release and lookup" do
    index = index()
    {:ok, lease} = B.acquire(index)
    :ok = :sys.suspend(index.pid)

    calls =
      for _ <- 1..64 do
        call = probed(fn -> B.inspect(index, %{timeout: 60_000}) end)
        event(call, :dispatched)
        call
      end

    assert B.lookup(lease, "a") == {:error, :busy}
    assert B.release(lease) == {:error, :busy}
    assert B.close(index) == {:error, :busy}
    :ok = :sys.resume(index.pid)

    for call <- calls do
      assert {:ok, _} = result(call)
      event(call, :freed)
    end

    assert :ok = B.release(lease)
  end
end
