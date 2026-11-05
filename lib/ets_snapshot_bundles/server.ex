defmodule EtsSnapshotBundles.Server do
  @moduledoc false
  use GenServer
  alias EtsSnapshotBundles.{Bundle, Lease}

  def start_link(index), do: GenServer.start_link(__MODULE__, index)

  @impl true
  def init(index) do
    case Bundle.build([]) do
      {:ok, table} ->
        {:ok,
         %{
           index: %{index | pid: self()},
           current: snapshot(0, table, 0, 0),
           retired: %{},
           leases: %{},
           monitors: %{}
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:bundle_request, instance, worker, tag, caller, cancel, operation}, state) do
    {result, next} =
      cond do
        instance != state.index.instance -> {{:error, :unavailable}, state}
        :atomics.get(cancel, 1) != 0 -> {{:error, :cancelled}, state}
        not Process.alive?(caller) -> {{:error, :cancelled}, state}
        true -> dispatch(operation, caller, state)
      end

    send(worker, {:bundle_result, tag, result})

    if operation == :close and result == :ok do
      {:stop, :normal, next}
    else
      {:noreply, next}
    end
  end

  def handle_info({:bundle_abandon, instance, worker, tag, ref, caller}, state) do
    next =
      case Map.get(state.leases, ref) do
        %{owner: ^caller} when instance == state.index.instance -> drop_lease(state, ref)
        _ -> state
      end

    send(worker, {:bundle_abandoned, tag})
    {:noreply, next}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Map.fetch(state.monitors, monitor) do
      {:ok, ref} -> {:noreply, drop_lease(state, ref)}
      :error -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp dispatch({:publish, entries, count, bytes, expected}, _caller, state) do
    current = state.current

    cond do
      expected != nil and expected != current.generation ->
        {{:error, :stale_generation}, state}

      current.pins > 0 and map_size(state.retired) >= state.index.limits.retired_limit ->
        {{:error, :pinned_limit}, state}

      true ->
        case Bundle.build(entries) do
          {:ok, table} ->
            retired =
              if current.pins == 0 do
                :ets.delete(current.table)
                state.retired
              else
                Map.put(state.retired, current.generation, current)
              end

            next = snapshot(current.generation + 1, table, count, bytes)
            {{:ok, next.generation}, %{state | current: next, retired: retired}}

          {:error, reason} ->
            {{:error, reason}, state}
        end
    end
  end

  defp dispatch(:acquire, caller, state) do
    if map_size(state.leases) >= state.index.limits.max_leases do
      {{:error, :lease_limit}, state}
    else
      ref = make_ref()
      monitor = Process.monitor(caller)
      generation = state.current.generation
      lease = %Lease{index: state.index, ref: ref, owner: caller, generation: generation}
      record = %{owner: caller, generation: generation, monitor: monitor}

      next = %{
        state
        | current: %{state.current | pins: state.current.pins + 1},
          leases: Map.put(state.leases, ref, record),
          monitors: Map.put(state.monitors, monitor, ref)
      }

      {{:ok, lease}, next}
    end
  end

  defp dispatch({:lookup, lease, key}, caller, state) do
    result =
      with :ok <- instance_matches(lease, state),
           :ok <- owns(lease, caller),
           {:ok, record} <- live_record(lease, state),
           :ok <- owns(record, caller) do
        bundle = find_snapshot(state, record.generation)

        case :ets.lookup(bundle.table, key) do
          [{^key, value}] -> {:ok, value}
          [] -> :not_found
        end
      end

    {result, state}
  end

  defp dispatch({:release, lease}, caller, state) do
    with :ok <- instance_matches(lease, state),
         true <- lease.owner == caller do
      case Map.fetch(state.leases, lease.ref) do
        {:ok, record} ->
          case owns(record, caller) do
            :ok -> {:ok, drop_lease(state, lease.ref)}
            error -> {error, state}
          end

        :error ->
          {:ok, state}
      end
    else
      false -> {{:error, :not_owner}, state}
      error -> {error, state}
    end
  end

  defp dispatch(:inspect, _caller, state) do
    retired_bytes = Enum.reduce(state.retired, 0, fn {_, bundle}, n -> n + bundle.bytes end)

    stats = %{
      generation: state.current.generation,
      current_keys: state.current.keys,
      current_payload_bytes: state.current.bytes,
      retired_payload_bytes: retired_bytes,
      retained_payload_bytes: state.current.bytes + retired_bytes,
      current_pins: state.current.pins,
      leases: map_size(state.leases),
      lease_monitors: map_size(state.monitors),
      pinned_retired_generations: map_size(state.retired),
      retired_generations: Enum.sort(Map.keys(state.retired)),
      table_count: 1 + map_size(state.retired),
      admission_in_use: :atomics.get(state.index.gate, 1),
      admission_capacity: 64,
      limits: state.index.limits
    }

    {{:ok, stats}, state}
  end

  defp dispatch(:close, _caller, state), do: {:ok, state}

  defp instance_matches(lease, state) do
    if lease.index.instance == state.index.instance and lease.index.pid == self(),
      do: :ok,
      else: {:error, :unavailable}
  end

  defp live_record(lease, state) do
    case Map.fetch(state.leases, lease.ref) do
      {:ok, %{generation: generation} = record} when generation == lease.generation ->
        {:ok, record}

      {:ok, _record} ->
        {:error, :invalid_handle}

      :error ->
        {:error, :stale_snapshot}
    end
  end

  defp owns(%{owner: caller}, caller), do: :ok
  defp owns(_, _), do: {:error, :not_owner}

  defp snapshot(generation, table, keys, bytes),
    do: %{generation: generation, table: table, keys: keys, bytes: bytes, pins: 0}

  defp find_snapshot(%{current: %{generation: generation} = bundle}, generation), do: bundle
  defp find_snapshot(state, generation), do: Map.fetch!(state.retired, generation)

  defp drop_lease(state, ref) do
    case Map.pop(state.leases, ref) do
      {nil, _} ->
        state

      {record, leases} ->
        Process.demonitor(record.monitor, [:flush])
        state = %{state | leases: leases, monitors: Map.delete(state.monitors, record.monitor)}

        if record.generation == state.current.generation do
          %{state | current: %{state.current | pins: state.current.pins - 1}}
        else
          bundle = Map.fetch!(state.retired, record.generation)

          if bundle.pins == 1 do
            :ets.delete(bundle.table)
            %{state | retired: Map.delete(state.retired, record.generation)}
          else
            %{
              state
              | retired:
                  Map.put(state.retired, record.generation, %{bundle | pins: bundle.pins - 1})
            }
          end
        end
    end
  end
end
