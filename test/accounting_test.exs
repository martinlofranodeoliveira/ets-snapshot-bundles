defmodule EtsSnapshotBundles.AccountingTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  import EtsSnapshotBundles.TestHelpers

  test "retained payload and real ETS tables track pinned generations exactly" do
    index = index(%{retired_limit: 2})
    assert {:ok, 1} = B.publish(index, [{"a", "123"}])
    {:ok, one} = B.acquire(index)
    assert {:ok, 2} = B.publish(index, [{"bb", "12345"}])
    {:ok, two} = B.acquire(index)
    assert {:ok, 3} = B.publish(index, [{"ccc", "1234567"}])
    stats = stats(index)
    assert stats.current_payload_bytes == 10
    assert stats.retired_payload_bytes == 11
    assert stats.retained_payload_bytes == 21
    assert stats.retired_generations == [1, 2]
    assert stats.table_count == 3
    assert length(owned_tables(index)) == 3
    assert :ok = B.release(one)
    assert stats(index).retained_payload_bytes == 17
    assert length(owned_tables(index)) == 2
    assert :ok = B.release(two)
    assert stats(index).retained_payload_bytes == 10
    assert length(owned_tables(index)) == 1
  end

  test "repeated releases, acquisitions and admission cycles keep no token history" do
    index = index()

    for generation <- 1..200 do
      assert {:ok, ^generation} = B.publish(index, [{"k", "synthetic"}])
      {:ok, lease} = B.acquire(index)
      assert B.lookup(lease, "k") == {:ok, "synthetic"}
      assert :ok = B.release(lease)
      assert :ok = B.release(lease)
      assert B.lookup(lease, "k") == {:error, :stale_snapshot}
      state = :sys.get_state(index.pid)
      assert state.leases == %{}
      assert state.monitors == %{}
      assert state.retired == %{}
      assert map_size(state) == 5
      assert :atomics.get(index.gate, 1) == 0
      assert length(owned_tables(index)) == 1
      {:monitors, monitors} = Process.info(index.pid, :monitors)
      assert monitors == []
    end
  end

  test "inspection counts its own admission slot but completion returns it" do
    index = index()
    stats = stats(index)
    assert stats.admission_in_use == 1
    assert stats.admission_capacity == 64
    assert :atomics.get(index.gate, 1) == 0
  end
end
