defmodule EtsSnapshotBundles.TestHelpers do
  import ExUnit.Assertions
  alias EtsSnapshotBundles, as: Bundles
  alias EtsSnapshotBundles.Admission

  def index(options \\ %{}) do
    {:ok, index} = Bundles.start_link(options)
    Process.unlink(index.pid)

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(index.pid) do
        monitor = Process.monitor(index.pid)
        Process.exit(index.pid, :kill)
        assert_receive {:DOWN, ^monitor, :process, _, _}, 3000
      end
    end)

    index
  end

  def stats(index) do
    {:ok, stats} = Bundles.inspect(index)
    stats
  end

  def owned_tables(index) do
    Enum.filter(:ets.all(), &(:ets.info(&1, :owner) == index.pid))
  end

  def reader do
    pid = spawn(fn -> reader_loop() end)
    ExUnit.Callbacks.on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    pid
  end

  defp reader_loop do
    receive do
      {:invoke, from, ref, function} ->
        send(from, {:invoked, ref, function.()})
        reader_loop()
    end
  end

  def ask(pid, function) do
    ref = make_ref()
    send(pid, {:invoke, self(), ref, function})

    receive do
      {:invoked, ^ref, result} -> result
    after
      3000 -> flunk("reader did not answer")
    end
  end

  def probed(function, pause \\ nil) do
    parent = self()
    ref = make_ref()

    {caller, monitor} =
      spawn_monitor(fn ->
        Process.put({Admission, :probe}, {parent, ref, pause})
        send(parent, {:call_result, ref, function.()})
      end)

    ExUnit.Callbacks.on_exit(fn -> if Process.alive?(caller), do: Process.exit(caller, :kill) end)
    %{caller: caller, monitor: monitor, ref: ref}
  end

  def event(call, stage) do
    ref = call.ref
    assert_receive {:probe, ^ref, ^stage, worker}, 3000
    worker
  end

  def result(call) do
    ref = call.ref
    assert_receive {:call_result, ^ref, result}, 3000
    result
  end

  def dead(call) do
    monitor = call.monitor
    caller = call.caller
    assert_receive {:DOWN, ^monitor, :process, ^caller, _}, 3000
  end

  def expire(worker, call), do: send(worker, {:probe_expire, call.ref})
  def continue(worker, call), do: send(worker, {:probe_continue, call.ref})
end
