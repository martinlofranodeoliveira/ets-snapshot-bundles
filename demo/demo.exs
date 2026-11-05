defmodule SnapshotDemo do
  alias EtsSnapshotBundles, as: Bundles

  defp check(actual, expected) do
    if actual != expected do
      raise "demo assertion failed: expected #{inspect(expected)}, got #{inspect(actual)}"
    end

    Process.put(:demo_checks, Process.get(:demo_checks, 0) + 1)
  end

  def run do
    {:ok, index} = Bundles.start_link(%{retired_limit: 1})

    try do
      check(Bundles.publish(index, [{"a", "old-a"}, {"b", "old-b"}]), {:ok, 1})
      {:ok, first} = Bundles.acquire(index)
      check(Bundles.publish(index, [{"a", "new-a"}, {"b", "new-b"}]), {:ok, 2})
      {:ok, second} = Bundles.acquire(index)
      check(Bundles.lookup(first, "a"), {:ok, "old-a"})
      check(Bundles.lookup(first, "b"), {:ok, "old-b"})
      check(Bundles.lookup(second, "a"), {:ok, "new-a"})
      check(Bundles.lookup(second, "b"), {:ok, "new-b"})
      check(Bundles.publish(index, [{"a", "third-a"}]), {:error, :pinned_limit})
      check(Bundles.release(first), :ok)
      check(Bundles.lookup(first, "a"), {:error, :stale_snapshot})
      check(Bundles.publish(index, [{"a", "third-a"}]), {:ok, 3})
      check(Bundles.lookup(second, "a"), {:ok, "new-a"})
      check(Bundles.release(second), :ok)
      {:ok, stats} = Bundles.inspect(index)
      check({stats.generation, stats.leases, stats.table_count}, {3, 0, 1})
      check(Bundles.close(index), :ok)
      count = Process.get(:demo_checks)
      IO.puts("Runtime: Elixir #{System.version()}, OTP #{System.otp_release()}")
      IO.puts("PASS: #{count} checks; coherent generations, pin-limit rejection and retry.")

      IO.puts(
        "{\"status\":\"ok\",\"checks\":#{count},\"current_generation\":3,\"retained_tables\":1}"
      )
    after
      if Process.alive?(index.pid), do: Bundles.close(index)
    end
  end
end

SnapshotDemo.run()
