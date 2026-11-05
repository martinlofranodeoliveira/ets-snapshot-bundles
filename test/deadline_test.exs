defmodule EtsSnapshotBundles.DeadlineTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "queued acquire timeout retains its slot until discarded, with no pin" do
    index = index()
    :ok = :sys.suspend(index.pid)
    call = probed(fn -> B.acquire(index, %{timeout: 60_000}) end)
    worker = event(call, :dispatched)
    expire(worker, call)
    event(call, :cancelled)
    assert result(call) == {:error, :timeout}
    assert :atomics.get(index.gate, 1) == 1
    :ok = :sys.resume(index.pid)
    event(call, :freed)
    assert stats(index).leases == 0
    assert stats(index).lease_monitors == 0
  end

  test "timed-out acquire is rolled back even when the surviving caller never got its offer" do
    index = index()
    parent = self()
    ref = make_ref()
    reader = reader()

    # ask/2 executes in the reader; the reader remains alive after the timeout.
    controller =
      spawn(fn ->
        result =
          ask(reader, fn ->
            Process.put({EtsSnapshotBundles.Admission, :probe}, {parent, ref, :after_result})
            B.acquire(index, %{timeout: 60_000})
          end)

        send(parent, {:reader_result, result})
      end)

    assert_receive {:probe, ^ref, :after_result, worker}, 3000
    assert stats(index).leases == 1
    send(worker, {:probe_expire, ref})
    assert_receive {:reader_result, {:error, :timeout}}, 3000
    assert_receive {:probe, ^ref, :freed, ^worker}, 3000
    assert Process.alive?(reader)
    assert stats(index).leases == 0
    assert stats(index).lease_monitors == 0
    assert :atomics.get(index.gate, 1) == 0
    monitor = Process.monitor(controller)
    assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 3000
  end

  test "reader death after acquire execution but before delivery removes its pin" do
    index = index()
    call = probed(fn -> B.acquire(index, %{timeout: 60_000}) end, :after_result)
    event(call, :after_result)
    assert stats(index).leases == 1
    Process.exit(call.caller, :kill)
    dead(call)
    event(call, :freed)
    assert stats(index).leases == 0
    assert stats(index).lease_monitors == 0
  end

  test "a publication may already be committed when its caller dies or times out" do
    for outcome <- [:death, :timeout] do
      index = index()

      call =
        probed(
          fn -> B.publish(index, [{"a", "committed"}], %{timeout: 60_000}) end,
          :after_result
        )

      worker = event(call, :after_result)
      assert stats(index).generation == 1

      case outcome do
        :death ->
          Process.exit(call.caller, :kill)
          dead(call)

        :timeout ->
          expire(worker, call)
          assert result(call) == {:error, :timeout}
      end

      event(call, :freed)
      {:ok, lease} = B.acquire(index)
      assert B.lookup(lease, "a") == {:ok, "committed"}
      assert :ok = B.release(lease)
      assert length(owned_tables(index)) == 1
    end
  end

  test "deadline before dispatch sends no request and releases the slot" do
    index = index()
    call = probed(fn -> B.acquire(index, %{timeout: 60_000}) end, :before_dispatch)
    worker = event(call, :before_dispatch)
    expire(worker, call)
    assert result(call) == {:error, :timeout}
    event(call, :freed)
    assert stats(index).leases == 0
    refute_receive {:probe, _, :dispatched, _}, 0
  end
end
