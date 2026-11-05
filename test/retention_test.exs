defmodule EtsSnapshotBundles.RetentionTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "pin-limit rejection and retry use generation count, not lease count" do
    index = index(%{retired_limit: 1})
    assert {:ok, 1} = B.publish(index, [{"a", "one"}])
    {:ok, first} = B.acquire(index)
    {:ok, extra} = B.acquire(index)
    assert {:ok, 2} = B.publish(index, [{"a", "two"}])
    {:ok, second} = B.acquire(index)
    before = stats(index)
    assert before.retired_generations == [1]
    assert B.publish(index, [{"a", "three"}]) == {:error, :pinned_limit}
    assert stats(index) == before
    assert :ok = B.release(first)
    assert B.publish(index, []) == {:error, :pinned_limit}
    assert :ok = B.release(extra)
    assert length(owned_tables(index)) == 1
    assert {:ok, 3} = B.publish(index, [{"a", "three"}])
    assert stats(index).retired_generations == [2]
    assert B.lookup(second, "a") == {:ok, "two"}
    assert :ok = B.release(second)
    assert length(owned_tables(index)) == 1
  end

  test "zero retired capacity permits unpinned replacement only" do
    index = index(%{retired_limit: 0})
    {:ok, lease} = B.acquire(index)
    assert B.publish(index, []) == {:error, :pinned_limit}
    assert :ok = B.release(lease)
    assert {:ok, 1} = B.publish(index, [])
    assert length(owned_tables(index)) == 1
  end

  test "reader DOWN reclaims a retired table after the server handles that signal" do
    index = index()
    assert {:ok, 1} = B.publish(index, [{"a", "one"}])
    reader = reader()
    {:ok, _lease} = ask(reader, fn -> B.acquire(index) end)
    assert {:ok, 2} = B.publish(index, [{"a", "two"}])
    assert stats(index).leases == 1
    assert length(owned_tables(index)) == 2

    # Suspend, then put the server's actual monitor DOWN in its mailbox before resuming.
    :ok = :sys.suspend(index.pid)
    state = :sys.get_state(index.pid)
    [monitor] = Map.keys(state.monitors)
    test_monitor = Process.monitor(reader)
    Process.exit(reader, :kill)
    assert_receive {:DOWN, ^test_monitor, :process, ^reader, :killed}
    assert_receive_down_in_mailbox(index.pid, monitor)
    :ok = :sys.resume(index.pid)
    after_down = stats(index)
    assert after_down.leases == 0
    assert after_down.lease_monitors == 0
    assert after_down.retired_payload_bytes == 0
    assert after_down.retired_generations == []
    assert length(owned_tables(index)) == 1
  end

  defp assert_receive_down_in_mailbox(pid, monitor, attempts \\ 1000)
  defp assert_receive_down_in_mailbox(_pid, _monitor, 0), do: flunk("missing server DOWN signal")

  defp assert_receive_down_in_mailbox(pid, monitor, attempts) do
    {:messages, messages} = Process.info(pid, :messages)

    if Enum.any?(messages, fn
         {:DOWN, ^monitor, :process, _, _} -> true
         _ -> false
       end) do
      :ok
    else
      assert_receive_down_in_mailbox(pid, monitor, attempts - 1)
    end
  end
end
