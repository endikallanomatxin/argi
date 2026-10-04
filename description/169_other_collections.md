# Other collections

The library may offer maps, sets, graphs, queues, and iterator helpers in
addition to the [list families](161_lists.md). Accepted contracts are described
below; exploratory collections are marked as ideas.

## Hash and equality policies

`HashPolicy<K>` supplies `hash(.self, .key) -> UIntNative` and
`eql(.self, .left, .right) -> Bool`. Equality must be an equivalence relation;
equal keys must hash equally. Policy results must remain stable while keys are
stored. Hash collisions are supported, but unstable equality or key mutation
cannot be repaired by the container.

Core supplies `UIntNativeHashPolicy`, `Int32HashPolicy`, and
`StringViewHashPolicy`. Integer policies encode the integer value without raw
memory access or native byte-order dependence. String hashing visits every byte
and equality compares complete recorded byte extents, including embedded NULs.
These are deterministic, non-keyed policies, not collision-attack defenses.
Applications can implement the same small contract for their own key types.
Borrowed string keys retain their backing lifetimes and must not be modified
while stored. Hashing does not transfer or acquire ownership of that storage.

## Maps

`HashMap<K, V, P>` stores implicitly copyable keys and values with an explicit
`P: HashPolicy<K>` instance. Construction takes `.policy`, `.allocator`, and an
optional `.capacity`. Capacity is the number of table slots, at least eight;
occupied load stays at most one half. The map owns its table and policy, but
copying a borrowed key or value does not acquire its backing storage.

- `put(.self, .key, .value, .allocator)` inserts or replaces a value. Replacement
  retains the existing key and does not allocate. Construction and growth
  report `out_of_memory`; failed growth preserves all existing entries.
- `get(.self, .key)` returns an optional copied value. `contains` tests membership.
- `get_ro_ref(.self, .key)` returns an optional borrowed value. Mutation and
  cleanup invalidate element borrows; acquire a new reference after mutation.
- `remove(.self, .key, .allocator)` reports whether an entry was removed.
- `length` reports entries, `capacity` reports slots, and
  `deinit(.self, .allocator)` releases the table and owned policy.

`HashMap` implements `Iterable<HashMapEntry<K, V>>`: `for entry in map`
visits copied `.key`/`.value` pairs. `to_key_iterator` and `to_value_iterator`
visit copied keys and values. Iteration scans table slots, skips deleted entries,
and does not call hashing or equality policies. Order is unspecified; iterators
allocate no storage and are not snapshots.

`to_ro_entry_iterator` returns borrowed entries with `.key: &K` and `.value: &V`.
`to_rw_entry_iterator` accepts a mutable map and returns `.key: &K` and
`.value: $&V`. Keys remain readonly so value edits cannot corrupt lookup policy
invariants. Direct edits through borrowed value references preserve iteration.
Every successful `put`, removal of an existing key, growth, and cleanup
invalidates existing iterators and entry references; reacquire them afterward.
Copied entries remain independent of table storage, while any borrowed state
inside their keys or values still needs its original backing storage.
`next` requires a preceding successful `has_next`; calling it at end aborts.

Keys and values with borrowed state require their backing storage to remain
live. Key contents must stay unchanged until removal or cleanup. Collisions and
deletions preserve lookup paths, and every probe is bounded by table capacity.
Owning keys and values use the separate owning families described below.


> [!IDEA]
> A map literal could use a form such as `("a" = 1, "b" = 2)`. Its relationship
> to struct literals, key typing, and allocation needs design.

## Sets

`HashSet<K, P>` uses the same key policy and storage implementation as
`HashMap`. Keys are implicitly copyable; borrowed keys keep their backing
lifetimes and must remain unchanged while stored. Construction accepts
`.policy`, `.allocator`, and optional `.capacity` with the map's slot-count
meaning and allocation errors.

`insert(.self, .key, .allocator)` returns an errable Boolean: true for a new key,
false when an equivalent key is already present. Duplicate insertion retains
the existing key, leaves length unchanged, and does not allocate. Failed growth
preserves membership. `contains`, `remove`, `length`, `capacity`, and `deinit`
have the corresponding map contracts. The set does not expose stored-key
references or acquire ownership of borrowed backing storage. It implements
`Iterable<K>` and visits copied keys through `for key in set`. Order, allocation,
exhaustion, and structural invalidation follow map iteration. Duplicate insertion
and unsuccessful removal do not change the table or invalidate an iterator.

## Graphs

> [!IDEA]
> Add graph collections; their representations and operations remain open.

## Queues

`RingBuffer<T>` is an owning FIFO queue with a fixed positive capacity. Its
constructor accepts `.capacity` and an explicit `.allocator`, reserves storage
once, and initializes no elements. Zero capacity reports `invalid_capacity`;
unrepresentable allocation sizes and allocation failures report `out_of_memory`.
Zero-sized elements remain distinct logical occupied slots.

- `push(.self, .value, .allocator)` moves a value into the next vacant slot.
  A full buffer reports `full`, retains its queued contents, and destroys the
  consumed argument using the supplied allocator where its cleanup needs one.
  It does not silently overwrite the oldest element or grow the buffer.
- `pop(.self)` moves the oldest value out, or reports `empty`. An extracted
  owning value is independent of the buffer storage and can outlive it.
- `length` and `capacity` report logical occupancy and fixed capacity.
- `get_ro_ref(.self, .index)` borrows an occupied element in FIFO order,
  or reports `out_of_bounds`. The buffer implements `Indexable<T>` and
  supports equality search when its elements satisfy that algorithm's contract.
- `deinit(.self, .allocator)` destroys the remaining occupied elements once
  and releases the backing allocation. Vacant slots are never read or dropped.

Push and pop do not allocate queue storage. Element cleanup may have its own
capability requirements. Structural operations may invalidate existing element
borrows; obtain a new borrow after mutation. Cleanup also invalidates borrows.
Returned indices carry no storage lifetime and can become stale after popping.
The allocation receipt, head, occupancy, and invalidation marker are private.

`Deque#(.t: T)` provides a growable owning queue with double-ended insertion
and removal. Growth relocates occupied elements in logical order and preserves
the old queue if allocation fails. See [growable deque](161_lists.md#growable-deque)
for its operations, borrowing rules, and consumed-argument behavior.

## SoA and AoS

> [!IDEA]
> Explore struct-of-arrays and array-of-structs layouts for collections with
> different access patterns. Their shape and selection rules remain open.

## Iterator helpers

> [!IDEA]
> Beyond the basic [iterator contract](44_control_flow.md), library adapters
> could provide zipping, enumeration, and sliding-window iteration.

## Owning hash maps and sets

`OwnedHashMap<K, V, P>` moves keys and values into owned table storage. Neither
needs to be implicitly copyable. `BorrowedHashPolicy<K>` hashes `.key: &K` and
compares `.left: &K`/`.right: &K`; policy methods never consume lookup keys.
The same stable equivalence and equal-hash obligations apply. Core provides
`StringHashPolicy` for owning Strings, and the integer policies implement both
copyable and borrowed contracts. The map owns its policy as well as its entries.

Construction takes `.policy`, `.allocator`, and optional `.capacity` (at least
eight slots). Occupied load remains at most one half. `reserve` requests a larger
slot capacity. Growth allocates all new storage before relocating any entry;
`out_of_memory` preserves the old entries and capacity. Entry relocation does
not copy or destroy their owning contents. Destructors may require the supplied
allocator; other reached cleanup capabilities retain their ordinary contracts.

`put(.self, .key, .value, .allocator)` consumes both input values on every
outcome. New insertion moves them into the table. Replacement destroys both the
previous key and value and installs the supplied equivalent key and new value,
without allocating table storage. Failed growth destroys consumed inputs and
preserves existing entries. This replacement rule differs from copyable
`HashMap`, which retains the existing key.

`contains(.self, .key: &K)` queries membership; `get_ro_ref` returns an optional
borrowed `&V`. `extract(.self, .key: &K)` removes an entry and returns an optional
owning `OwnedHashMapEntry<K, V>` containing `.key` and `.value`. The extracted
entry has independent ownership and can outlive the table. `remove` destroys
the matching entry and reports whether it existed. `length`, `capacity`, and
`deinit` follow the copyable map meanings. Cleanup destroys every remaining key,
value, and policy once and releases table storage. No owning key is exposed
through a mutable reference.

`for entry in map` visits borrowed `.key: &K`/`.value: &V` entries rather than
copies of the owners. Iteration allocates no storage, skips deleted slots, and
has unspecified table order. Iterators and returned references retain the table
shape dependency. Reacquire loans after mutating calls, including fallible ones:
safety summaries conservatively join their possible outcomes. Successful put,
removal, extraction, capacity-changing reserve, and cleanup invalidate loans.
`next` requires a successful `has_next` and aborts at exhaustion.

`OwnedHashSet<K, P>` owns keys using the same table. `insert(.self, .key,
.allocator)` consumes its argument and returns true only for new membership.
Duplicate insertion retains the stored key and destroys the supplied equivalent
key. Failed growth destroys the supplied key and preserves membership.
`contains`, `remove`, `reserve`, `length`, `capacity`, and `deinit` correspond to
map operations. `extract(.self, .key: &K)` returns the removed owning key.
`to_ro_pointer_iterator` visits readonly key references; it never copies owners.

Owning a key or value does not freeze borrowed state inside it. External backing
storage must remain live and key contents must remain unchanged while stored.
Ownership transfer supplies no new native allocation receipt or reference
validity beyond the original values' checked storage contracts.

For `OwnedHashMap<String, V, StringHashPolicy>`, `contains` and `get_ro_ref`
also accept `.key: StringView`. `get_ref(.self: $&map, .key: StringView)`
returns an optional mutable value reference. These probes allocate nothing,
retain the map shape dependency and never expose mutable keys. Editing a value
preserves table shape; insertion, removal, growth and cleanup invalidate its
borrowed references. The query text is used only for the lookup and is not
retained by the returned value reference.

## Borrowed bit sets

`BitSetView(.bytes, .count)` borrows initialized mutable byte storage for
`.count` bits and clears the bytes required by that range. Bit zero is the
low bit of the first byte. Insufficient storage reports `out_of_bounds`
before writing anything; size calculation cannot overflow. Storage beyond
the required bytes remains unchanged, and zero bits require no bytes.

`length` reports bit capacity. Checked `contains(.self, .index)` queries a bit;
`set(.self, .index, .value = true)` sets or clears it. Repeated writes are
idempotent, and invalid indices leave storage unchanged. `count_set` counts
only the recorded bit range, ignoring padding bits in the final byte. The
view allocates nothing and retains the backing storage's lifetime.
