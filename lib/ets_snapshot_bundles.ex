defmodule EtsSnapshotBundles do
  @moduledoc "Development version 0.1.0: immutable, process-bound ETS snapshots."
  import Kernel, except: [inspect: 1, inspect: 2]
  alias EtsSnapshotBundles.{Admission, Bundle, Index, Lease, Limits, Server}

  @doc "Starts a linked, unnamed owner and returns an instance handle, not a PID."
  def start_link(options \\ %{}) do
    with {:ok, limits} <- Limits.new(options) do
      index = %Index{
        pid: self(),
        instance: make_ref(),
        gate: :atomics.new(1, signed: false),
        limits: limits
      }

      case Server.start_link(index) do
        {:ok, pid} -> {:ok, %{index | pid: pid}}
        error -> error
      end
    end
  end

  @doc "Replaces the complete bundle. Only a bounded proper list of binary pairs is accepted."
  def publish(index, entries, options \\ %{})

  def publish(%Index{} = index, entries, options) do
    if valid_index?(index) do
      with {:ok, timeout, expected} <- Limits.request(options, true),
           {:ok, prepared, count, bytes} <- Bundle.prepare(entries, index.limits) do
        Admission.request(index, {:publish, prepared, count, bytes, expected}, timeout)
      end
    else
      {:error, :invalid_handle}
    end
  end

  def publish(_, _, _), do: {:error, :invalid_handle}

  @doc "Pins the current generation for the calling PID."
  def acquire(index, options \\ %{})

  def acquire(%Index{} = index, options) do
    if valid_index?(index), do: invoke(index, :acquire, options), else: {:error, :invalid_handle}
  end

  def acquire(_, _), do: {:error, :invalid_handle}

  @doc "Looks up a binary key in the lease's original generation."
  def lookup(lease, key, options \\ %{})

  def lookup(%Lease{} = lease, key, options) do
    cond do
      not valid_lease?(lease) -> {:error, :invalid_handle}
      not Bundle.key?(key) -> {:error, :invalid_key}
      true -> invoke(lease.index, {:lookup, lease, key}, options)
    end
  end

  def lookup(_, _, _), do: {:error, :invalid_handle}

  @doc "Idempotently releases a lease owned by the caller."
  def release(lease, options \\ %{})

  def release(%Lease{} = lease, options) do
    if valid_lease?(lease),
      do: invoke(lease.index, {:release, lease}, options),
      else: {:error, :invalid_handle}
  end

  def release(_, _), do: {:error, :invalid_handle}

  @doc "Returns logical accounting and bounded-state counters."
  def inspect(index, options \\ %{})

  def inspect(%Index{} = index, options) do
    if valid_index?(index), do: invoke(index, :inspect, options), else: {:error, :invalid_handle}
  end

  def inspect(_, _), do: {:error, :invalid_handle}

  @doc "Closes this instance. Existing leases subsequently return unavailable."
  def close(index, options \\ %{})

  def close(%Index{} = index, options) do
    if valid_index?(index), do: invoke(index, :close, options), else: {:error, :invalid_handle}
  end

  def close(_, _), do: {:error, :invalid_handle}

  defp invoke(index, operation, options) do
    with {:ok, timeout, _} <- Limits.request(options, false) do
      Admission.request(index, operation, timeout)
    end
  end

  defp valid_index?(%Index{
         pid: pid,
         instance: instance,
         gate: gate,
         limits:
           %{
             max_keys: max_keys,
             max_payload_bytes: max_payload_bytes,
             max_leases: max_leases,
             retired_limit: retired_limit
           } = limits
       }) do
    is_pid(pid) and is_reference(instance) and is_reference(gate) and map_size(limits) == 4 and
      is_integer(max_keys) and max_keys >= 0 and max_keys <= 65_536 and
      is_integer(max_payload_bytes) and max_payload_bytes >= 0 and
      max_payload_bytes <= 16_777_216 and
      is_integer(max_leases) and max_leases >= 1 and max_leases <= 4096 and
      is_integer(retired_limit) and retired_limit >= 0 and retired_limit <= 16
  end

  defp valid_index?(_), do: false

  defp valid_lease?(%Lease{index: index, ref: ref, owner: owner, generation: generation}) do
    valid_index?(index) and is_reference(ref) and is_pid(owner) and is_integer(generation) and
      generation >= 0
  end
end
