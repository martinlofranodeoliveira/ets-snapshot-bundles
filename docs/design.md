# Design

## Immutable generations

The GenServer owns every snapshot table. It validates publication preconditions, builds a new unnamed protected set completely, and only then changes the current snapshot in its serialized state. Existing leases refer to a generation, resolved to either the current snapshot or a retained snapshot. Publication never mutates an existing table. Lookup is also serialized through this owner in 0.1.0, so lease validation, table access and reclamation cannot race each other.

Validation runs in the invoking process before it creates an admission intermediary or copies a publication to the owner. The input is a bounded proper list, not an arbitrary Enumerable. Only after bounded count/shape/byte validation does a temporary MapSet detect duplicates. Invalid input allocates no snapshot table. Trusted callers must not mutate opaque handle limits.

The owner state has exactly five top-level fields: instance handle, current snapshot, retired snapshots, live leases and monitor-to-lease references. There is no generation archive or tombstone collection. A release deletes both reference mappings and demonitor-flushes its monitor. A final retired pin deletes that table immediately. The maximum completed table count is one plus the retired limit; building temporarily adds one more.

## Admission without a mailbox semaphore

A short-lived, unlinked intermediary makes a bounded compare-and-exchange attempt on an instance-local atomics counter. A failed attempt returns busy without contacting the owner. The successful intermediary monitors the caller and owner and holds the slot through dispatch, result, cancellation and any acquisition cleanup. Normal results are sent to the wrapper only after the slot has been returned. Deadline results are different: the caller is notified promptly while the intermediary continues owning the slot until outstanding work is resolved.

The request carries a shared one-cell cancellation flag. This permits a queued request to be discarded without maintaining an owner-side cancellation history. The owner checks cancellation and caller liveness immediately before executing. Those checks do not undo already executed publications. A result lost to timeout or caller death is harmless for reads; an acquired lease requires an abandonment message and acknowledgement before the slot is released. These cleanup messages are bounded by the same 64 slots.

The caller's wrapper uses a BEAM reply alias and a worker monitor. It has no second timeout that could race a successful acquire into an unseen permanent pin. Caller death automatically disables its reply alias. The intermediary is not linked to the caller, so killing that caller cannot interrupt token cleanup. Owner death makes cleanup unnecessary because its tables and lease monitors no longer exist.

At most 64 admitted intermediaries exist for an instance. An arbitrary number of invoking application processes can still create transient failed intermediaries; this library does not bound the application's process count. Directly killing private intermediaries, forging structures, changing atomics, sending raw protocol messages or reading protected ETS directly is outside the supported API and security boundary.

## Deterministic race tests

Test builds alone read a process-dictionary probe at `{EtsSnapshotBundles.Admission, :probe}`. Its value is `{observer_pid, reference, pause_stage}`. Stages are `before_dispatch` and `after_result`; all observed workers also emit `dispatched`, `cancelled` and `freed` events. A paused worker accepts `{:probe_continue, reference}` or `{:probe_expire, reference}`. The latter injects the same cancellation path as a deadline message, avoiding a timing-based race test. Normal builds do not read probes or emit probe events.

These are private test seams, not supported API options. They pause only intermediaries, leaving the owner able to report real pins and payload. Tests also use OTP system suspension to prove queued-work behavior: they observe dispatch, force cancellation, verify that the counter remains full, resume the owner, then observe cleanup completion. For reader death, a test suspends the owner and observes its actual monitor DOWN in the mailbox before resuming and inspecting. There are no timing sleeps, lease expiry clocks or manually fabricated DOWN messages.

Tests inspect actual ETS ownership and owner monitor state, not just public counters. Repeated acquisition/release cycles check that no history grows. All fixtures are synthetic.

## Failure model and tradeoffs

Allocation system-limit errors during table construction preserve current. An unexpected owner fault destroys all tables, making every old handle unavailable rather than recovering a possibly inconsistent state. The caller/owner monitor protocol has no disk recovery. Long-lived readers intentionally exert backpressure through the retired-generation bound. Request deadlines cannot force a suspended owner to finish work; slots stay occupied instead of allowing an unbounded supported queue.

Routing lookups through the owner costs serialization but keeps the first contract small and auditable. A direct ETS fast path would require a separate safe release/read protocol; it is deliberately not provided. Logical payload accounting is predictable but not a measurement of VM resident memory, especially for sub-binaries and message copies.

## Primary references

- [Elixir GenServer](https://hexdocs.pm/elixir/GenServer.html)
- [OTP ETS](https://www.erlang.org/doc/apps/stdlib/ets.html)
- [OTP processes, monitors and signals](https://www.erlang.org/doc/system/ref_man_processes.html)

These references describe the primitives, not a claim that this library implements a broader external standard.
