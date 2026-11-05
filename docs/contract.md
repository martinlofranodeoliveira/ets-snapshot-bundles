# Contract — development version 0.1.0

## Scope and handles

The contract is for local, trusted BEAM code calling `EtsSnapshotBundles`. No process registration, disk storage or external service is used. `start_link(limits \\ %{})` returns `{:ok, index}` or an error; `index` is an opaque instance handle containing the exact owner PID and a fresh reference token. It is linked to the starter. It is not a Supervisor-compatible child-start return value. The owner starts with one empty protected ETS table at generation 0. A restart requires a new call and creates a distinct instance.

Do not mutate or synthesize handle fields. Instance mismatches are nevertheless rejected, so old handles cannot silently resolve to a replacement process or table. A dead instance produces `{:error, :unavailable}` for otherwise valid operations. Argument validation can reject earlier. There is no registry-based reconnection.

## API

All options are maps, never keyword lists. Ordinary options allow only `timeout`, an integer from 0 through 60,000 milliseconds, default 5,000. Publication additionally allows `expected_generation`, nil or a nonnegative integer. Unknown options return `{:error, :invalid_options}`.

- `publish(index, entries, options \\ %{})`: returns `{:ok, next_generation}`. Replaces every key; omitted keys disappear. Even an empty or identical publication advances the generation once. `entries` must be a proper list of `{binary_key, binary_value}` tuples. No Enumerable callbacks run. At most `max_keys + 1` list cells are examined before count rejection. Shape, field sizes and accumulated logical bytes are validated before duplicate detection, ETS allocation or owner dispatch. Duplicate byte-identical keys return `duplicate_key`. A provided expected generation must equal the current generation when processed, otherwise `stale_generation`. A failed comparison never advances state.
- `acquire(index, options \\ %{})`: returns `{:ok, lease}` for the current generation, or `lease_limit`. The lease belongs to the actual calling PID, not its admission intermediary.
- `lookup(lease, key, options \\ %{})`: returns `{:ok, binary_value}`, `:not_found`, or an error. The lookup uses the lease's original pinned table. A live lease used by another PID returns `not_owner`. A missing lease reference returns `stale_snapshot`, without falling back to current. Key validation returns `invalid_key` for non-binaries or more than 128 bytes.
- `release(lease, options \\ %{})`: returns `:ok` for the owning PID, including repeated releases of that handle in a live instance. A foreign PID returns `not_owner`. No released-reference tombstone is retained. Once released, future lookups return `stale_snapshot`.
- `inspect(index, options \\ %{})`: returns `{:ok, stats}` with the fields below.
- `close(index, options \\ %{})`: returns `:ok` when processed and terminates the instance normally. All tables and leases disappear. Later valid operations return `unavailable`.

Malformed top-level handles return `invalid_handle`. Struct internals are opaque rather than a general hostile-term decoding interface.

## Binary and configuration limits

Empty binaries and arbitrary binary bytes are allowed. Keys are at most 128 bytes, values at most 4096 bytes. Logical payload is the sum of `byte_size(key) + byte_size(value)` over accepted distinct entries. It excludes all ETS, term, allocator, monitor, message and backing-binary overhead.

| Limit | Default | Accepted configuration range |
| --- | ---: | ---: |
| `max_keys` | 4096 | 0–65536 |
| `max_payload_bytes` | 1048576 | 0–16777216 |
| `max_leases` | 128 | 1–4096 |
| `retired_limit` | 2 | 0–16 |
| admission slots | 64 | fixed |

Configuration is a map with only the four configurable keys. A retired generation exists only while pinned. Publication returns `pinned_limit` if the current generation is pinned and retiring it would exceed `retired_limit`. Multiple leases on one generation consume multiple lease slots but just one retired-generation slot. An unpinned current generation can always be replaced with respect to this limit.

There is at most one current table, one transient building table and `retired_limit` retired tables. Each table is independently subject to the per-bundle key and byte limits. Completed operations retain at most `(retired_limit + 1) * max_payload_bytes` logical bytes; construction can temporarily add another bundle. An unpinned retired table is deleted in the same handler that removes its final pin. No table IDs are exposed by leases.

## Admission, timeout and death

Every ordinary operation, including inspection, lookup, release and close, claims one of 64 atomic slots before sending an owner request. Contention has a finite 64-CAS retry budget; `busy` can therefore also reflect extreme contention, not just full capacity. Invalid requests fail before admission. Each invocation briefly creates one intermediary; there is no admission waiting queue. This bounds supported outstanding owner work, not arbitrary concurrent invoking processes, raw messages or total VM resources.

An intermediary monitors the caller and exact owner. A caller dying before dispatch cannot strand a slot. After dispatch, caller death or request timeout marks a shared cancellation flag. The owner skips work if it observes that flag or a dead caller before execution. If work is already running or completed, publication is not rolled back. Timeout or caller death can therefore leave a publication committed. Reconcile with inspection and an expected generation; do not retry blindly.

Timeout is decided by the intermediary's deadline message versus the result it handles, not a hard wall-clock response guarantee. The wrapper does not have an independent timeout that can abandon an acquired lease. After a timeout has been returned, its slot remains held until the owner responds and any acquired lease has been abandoned and acknowledged, or until owner death. This includes queued timeout and surviving callers. If execution produced an acquisition before cancellation, the intermediary explicitly removes that pin. If an acquisition has already been delivered successfully, the owner's reader monitor handles any subsequent caller death.

The owner has one monitor per live lease, bounded by `max_leases`. Its DOWN handler removes that lease and reclaims any newly unpinned retired table. There are no lease clocks, expiry decisions, renewal operations, released-handle histories or completed-request histories. Owner death destroys its ETS tables and monitors; intermediaries observe DOWN and release slots. An indefinitely suspended live owner can hold all slots indefinitely after timeouts: this is intentional bounded backpressure, not automatic recovery.

## Inspection fields

`generation`, `current_keys`, `current_payload_bytes`, `current_pins`, `retired_payload_bytes`, `retained_payload_bytes`, `leases`, `lease_monitors`, `pinned_retired_generations`, `retired_generations` (ascending), `table_count`, `admission_in_use`, `admission_capacity`, and `limits`.

Inspection runs through admission and counts its own slot. Other concurrently completing intermediaries can affect `admission_in_use`; it is an instantaneous observation, not a completion barrier. All other inspection fields describe one serialized owner state. No building table is visible to inspection because publication handlers do not interleave.

## Errors and ordering

Publication validation errors are `invalid_entries`, `invalid_entry`, `too_many_keys`, `key_too_large`, `value_too_large`, `payload_limit`, and `duplicate_key`. Count/shape/size validation precedes duplicate detection; duplicate detection precedes expected-generation and pin checks. Expected-generation checks precede pin checks. A handled ETS system-limit allocation failure returns `resource_limit` without replacing current. Unexpected internal faults fail the owner; they do not expose a partially published table.

Ordinary calls may also return `busy`, `timeout`, `unavailable`, or argument/ownership errors listed above. Internal `cancelled` results are drained by intermediaries, not delivered as a normal cancellation API. Release or close that timed out may already have taken effect. No durability, distributed consistency, confidentiality against other VM code or broad standards compliance is claimed.
