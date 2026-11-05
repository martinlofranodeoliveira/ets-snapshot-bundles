defmodule EtsSnapshotBundles.Admission do
  @moduledoc false
  alias EtsSnapshotBundles.Lease
  @capacity 64
  @test_mode Mix.env() == :test

  def capacity, do: @capacity

  def request(index, operation, timeout) do
    caller = self()
    reply = :erlang.alias()
    probe = if @test_mode, do: Process.get({__MODULE__, :probe}), else: nil

    {_worker, monitor} =
      spawn_monitor(fn ->
        outcome =
          if claim(index.gate, @capacity) do
            try do
              run(index, caller, reply, operation, timeout, probe)
            after
              :atomics.sub(index.gate, 1, 1)
              notify(probe, :freed)
            end
          else
            {:reply, {:error, :busy}}
          end

        case outcome do
          {:reply, result} -> send(reply, {reply, result})
          :silent -> :ok
        end
      end)

    receive do
      {^reply, result} ->
        Process.demonitor(monitor, [:flush])
        :erlang.unalias(reply)
        result

      {:DOWN, ^monitor, :process, _pid, _reason} ->
        :erlang.unalias(reply)
        {:error, :unavailable}
    end
  end

  # A fixed retry budget means contention itself cannot create a waiting queue.
  defp claim(_gate, 0), do: false

  defp claim(gate, attempts) do
    current = :atomics.get(gate, 1)

    if current >= @capacity do
      false
    else
      case :atomics.compare_exchange(gate, 1, current, current + 1) do
        :ok -> true
        _ -> claim(gate, attempts - 1)
      end
    end
  end

  defp run(index, caller, reply, operation, timeout, probe) do
    caller_monitor = Process.monitor(caller)
    owner_monitor = Process.monitor(index.pid)
    tag = make_ref()
    timer = Process.send_after(self(), {:deadline, tag}, timeout)

    context = %{
      index: index,
      caller: caller,
      reply: reply,
      operation: operation,
      caller_monitor: caller_monitor,
      owner_monitor: owner_monitor,
      tag: tag,
      cancel: :atomics.new(1, signed: false),
      probe: probe
    }

    try do
      case checkpoint(context, :before_dispatch) do
        :go ->
          cond do
            not Process.alive?(caller) ->
              :silent

            not Process.alive?(index.pid) ->
              {:reply, {:error, :unavailable}}

            true ->
              send(index.pid, {
                :bundle_request,
                index.instance,
                self(),
                tag,
                caller,
                context.cancel,
                operation
              })

              notify(probe, :dispatched)
              await(context)
          end

        :timeout ->
          {:reply, {:error, :timeout}}

        :dead ->
          :silent

        :unavailable ->
          {:reply, {:error, :unavailable}}
      end
    after
      Process.cancel_timer(timer, async: false, info: false)
      Process.demonitor(caller_monitor, [:flush])
      Process.demonitor(owner_monitor, [:flush])
    end
  end

  defp await(context) do
    tag = context.tag
    caller_monitor = context.caller_monitor
    owner_monitor = context.owner_monitor
    probe_ref = probe_ref(context.probe)

    receive do
      {:bundle_result, ^tag, result} ->
        if context.operation == :close and result == :ok do
          receive do
            {:DOWN, ^owner_monitor, :process, _pid, _reason} -> :ok
          end
        end

        case checkpoint(context, :after_result) do
          :go ->
            {:reply, result}

          :timeout ->
            expire(context, {:result, result})

          :dead ->
            cancel(context)
            cleanup(context, result)
            :silent

          :unavailable ->
            {:reply, {:error, :unavailable}}
        end

      {:deadline, ^tag} ->
        expire(context, :pending)

      {:probe_expire, ref} when @test_mode and ref == probe_ref ->
        expire(context, :pending)

      {:DOWN, ^caller_monitor, :process, _pid, _reason} ->
        cancel(context)
        drain(context)
        :silent

      {:DOWN, ^owner_monitor, :process, _pid, _reason} ->
        {:reply, {:error, :unavailable}}
    end
  end

  defp expire(context, pending) do
    cancel(context)
    send(context.reply, {context.reply, {:error, :timeout}})

    case pending do
      :pending -> drain(context)
      {:result, result} -> cleanup(context, result)
    end

    :silent
  end

  defp cancel(context) do
    :atomics.put(context.cancel, 1, 1)
    notify(context.probe, :cancelled)
  end

  defp drain(context) do
    tag = context.tag
    owner_monitor = context.owner_monitor

    receive do
      {:bundle_result, ^tag, result} -> cleanup(context, result)
      {:DOWN, ^owner_monitor, :process, _pid, _reason} -> :ok
    end
  end

  defp cleanup(context, {:ok, %Lease{} = lease}) do
    send(context.index.pid, {
      :bundle_abandon,
      context.index.instance,
      self(),
      context.tag,
      lease.ref,
      context.caller
    })

    tag = context.tag
    owner_monitor = context.owner_monitor

    receive do
      {:bundle_abandoned, ^tag} -> :ok
      {:DOWN, ^owner_monitor, :process, _pid, _reason} -> :ok
    end
  end

  defp cleanup(_context, _result), do: :ok

  # Compiled out of normal builds. Tests can pause a worker, not the protocol.
  defp checkpoint(context, stage) do
    notify(context.probe, stage)

    case context.probe do
      {_observer, ref, ^stage} ->
        caller_monitor = context.caller_monitor
        owner_monitor = context.owner_monitor
        tag = context.tag

        receive do
          {:probe_continue, ^ref} -> :go
          {:probe_expire, ^ref} -> :timeout
          {:deadline, ^tag} -> :timeout
          {:DOWN, ^caller_monitor, :process, _pid, _reason} -> :dead
          {:DOWN, ^owner_monitor, :process, _pid, _reason} -> :unavailable
        end

      _ ->
        :go
    end
  end

  if @test_mode do
    defp notify({observer, ref, _pause}, event),
      do: send(observer, {:probe, ref, event, self()})

    defp notify(_, _), do: :ok
  else
    defp notify(_, _), do: :ok
  end

  defp probe_ref({_observer, ref, _pause}), do: ref
  defp probe_ref(_), do: nil
end
