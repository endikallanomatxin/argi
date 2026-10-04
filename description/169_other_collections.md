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

Keys and values with borrowed state require their backing storage to remain
live. Key contents must stay unchanged until removal or cleanup. Collisions and
deletions preserve lookup paths, and every probe is bounded by table capacity.
Owning keys and values require a separate ownership contract before support.


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
references or acquire ownership of borrowed backing storage.

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
