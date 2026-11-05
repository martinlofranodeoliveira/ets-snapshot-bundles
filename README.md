# ETS Snapshot Bundles

Development version **0.1.0** — an original, dependency-free Elixir library by [Lofrano Tecnologia](https://lofranotecnologia.com.br).

An unnamed GenServer owns immutable protected ETS tables. A reader acquires a process-bound lease and can inspect several keys without mixing generations. Complete-bundle publication is atomic relative to supported operations. Reader monitors reclaim pins; explicit limits bound retained generations, leases and admitted requests.

[Português](README.pt-BR.md) · [Exact contract](docs/contract.md) · [Design](docs/design.md)

## Install, test and demonstrate

Requires Elixir 1.18 or newer and a compatible OTP runtime. The compatibility CI matrix uses the official `elixir:1.18` and `elixir:1.20.5` images. No Hex package, database, model, API, credentials or network access is needed to compile or run this project.

From the project directory:

```sh
mix compile
mix test --seed 0
mix run demo/demo.exs
```

For a local application, use a Mix path dependency:

```elixir
{:ets_snapshot_bundles, path: "../ets-snapshot-bundles"}
```

The demo uses only synthetic strings and raises on any failed assertion. Its stable output lines are:

```text
PASS: 14 checks; coherent generations, pin-limit rejection and retry.
{"status":"ok","checks":14,"current_generation":3,"retained_tables":1}
```

It also prints the active Elixir and OTP versions. Image digest and runtime recording are described in [runtime notes](docs/runtime.md).

## Usage

```elixir
alias EtsSnapshotBundles, as: Bundles

{:ok, index} = Bundles.start_link(%{retired_limit: 1})
{:ok, 1} = Bundles.publish(index, [{"a", "old-a"}, {"b", "old-b"}])
{:ok, lease} = Bundles.acquire(index)
{:ok, 2} = Bundles.publish(index, [{"a", "new-a"}, {"b", "new-b"}],
  %{expected_generation: 1})
{:ok, "old-a"} = Bundles.lookup(lease, "a")
{:ok, "old-b"} = Bundles.lookup(lease, "b")
:ok = Bundles.release(lease)
{:error, :stale_snapshot} = Bundles.lookup(lease, "a")
{:ok, stats} = Bundles.inspect(index)
1 = stats.table_count
:ok = Bundles.close(index)
```

Acquire, use and release a lease in the **same process**. Use `try/after` around reader work if explicit early reclamation is important. Owner death also releases its leases. An index's `start_link/1` returns an instance handle, **not** the usual `{:ok, pid}` child-start result; it is not directly a supervisor child specification.

```elixir
{:ok, lease} = Bundles.acquire(index, %{timeout: 1000})
try do
  Bundles.lookup(lease, "route")
after
  Bundles.release(lease)
end
```

Defaults: 4,096 entries, 1 MiB logical key-plus-value bytes per bundle, 128 leases, two pinned retired generations, 64 admission slots. Keys are binaries up to 128 bytes; values are binaries up to 4 KiB. Publication accepts only a bounded proper list of binary pairs, never arbitrary Enumerable input. Duplicate keys reject the entire publication.

## Rationale and limits

Tables are built fully before switching the current generation. Admission uses short-lived monitored intermediaries and a fixed atomic counter, rather than placing unlimited callers in a semaphore server's mailbox. Timeout does not release a slot while its request remains queued. A timed-out acquire is discarded or explicitly rolled back, including when its caller remains alive.

All operations, including lookups, go through the owner in this version. This deliberately favors a small, auditable lease/reclamation protocol over a lock-free read path. There are no throughput or latency claims.

Limits cover supported outstanding requests and logical payload, not the entire BEAM heap, transient message copies, binary backing storage, scheduler delays or malicious raw mailbox traffic. Each invoking process briefly creates one intermediary even when admission fails. A long-lived reader can block publication. Protected ETS is not a confidentiality boundary against trusted code in the same VM.

No persistence, replication, distributed consensus, lease expiry, tenant isolation, merge rules or transparent recovery is implemented. An owner restart starts an empty generation 0 with a different instance token. Old handles return `unavailable`. Timeouts are request decisions, not lease expiry; a timed-out publication may already have committed. Reconcile using inspection and compare-and-publish rather than assuming timeout means rollback.

MIT, copyright 2026 Lofrano Tecnologia. General contact: [official homepage](https://lofranotecnologia.com.br). Security reporting: [SECURITY.md](SECURITY.md).
