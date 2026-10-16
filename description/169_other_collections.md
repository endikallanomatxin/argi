# Other collections

The library may offer maps, sets, graphs, queues, and iterator helpers in
addition to the [list families](161_lists.md). Accepted contracts are described
below; exploratory collections are marked as ideas.

## Hash and equality policies

`HashPolicy#(P, K)` associates one implicitly copyable `Query` type with a
policy and stored key. Its operations are:

- `query(.self, .key: &K) -> Query` projects a stored key without consuming it.
- `hash(.self, .key: Query) -> UIntNative` hashes the canonical representation.
- `equal(.self, .left: Query, .right: Query) -> Bool` compares representations.

Insertion and lookup use these same operations. Equality must be an equivalence
relation; equal queries must hash equally. Projection, hashing, and equality
must remain stable while keys are stored. Hash collisions are supported, but
unstable equality or key mutation cannot be repaired by the container.

`Hasher#(State)` consumes bytes and finishes a digest. `Hashable#(Key, State)`
feeds a key's canonical representation to that state. Hashing alone does not
require equality. Equal keys must feed identical byte streams; composite keys
must delimit variable-length fields. Integers feed their own width in canonical
little-endian order, including two's-complement signed values; String and StringView feed identical representations, including NULs.

`StandardHashPolicy` implements HashPolicy generically for any key satisfying
Hashable with StandardHasher and borrowed Equal evidence. A private composed
contract collects these requirements; Hashable remains independent. The hasher
uses [FNV-1a-64](https://www.ietf.org/archive/id/draft-eastlake-fnv-25.html) with an
explicit offset basis (default 14695981039346656037). Narrow native digests fold
all state bits. It is not cryptographic or collision-attack-resistant;
there is no implicit randomness or capability acquisition. Hashes are table
implementation details, not persistent identifiers.

Applications define Hashable once for their key, typically generically over any
Hasher. They need a custom HashPolicy only to change hashing/equality semantics
for a particular map. Borrowed key storage must remain live and unchanged.

The standard policy uses `&K` queries for general keys and `StringView` queries
for both `String` and `StringView`. Text callers explicitly use `view(&key)`
when starting with an owning string. A custom policy may choose another canonical
representation, such as an integer identifier for a larger stored key. Stored
keys need not be implicitly copyable; projection preserves their contents.

## Maps

`HashMap#(.key: K, .value: V)()` uses StandardHashPolicy without a policy argument.
A custom `.policy` argument infers the omitted static policy type. Only the
standard-policy Init permits omitting the policy value; custom policies are
required inputs. Both conformances delegate storage initialization to one helper. Explicit
`.policy: P` remains available for annotations and fully specified construction.
The map stores keys and values using `HashPolicy#(P, K)`.
Neither element type must be implicitly copyable. Construction takes `.policy`,
`.allocator` (explicitly or through `assume allocator`), and optional `.capacity` (at least eight slots). The map owns its
entries, policy, and storage. Borrowed state inside elements retains its original
lifetime obligations; stored key contents must remain unchanged.

- `put(.self, .key, .value, .allocator)` consumes its input values on every
  outcome. Pass noncopyable values with `~`. Replacement destroys the previous
  key and value and installs the supplied pair without allocating table storage.
  Failed growth destroys the supplied inputs and preserves existing entries.
- `contains(.self, .key: Query)` queries membership. `get_reference` returns `?&V`.
  `get` returns `?V` only when V is implicitly copyable.
- `extract(.self, .key: Query)` returns `?HashMapEntry#(K, V)`, transferring the
  removed entry. `remove(.self, .key: Query, .allocator)` destroys it instead.
- `reserve` grows slot capacity. All allocations complete before relocation;
  allocation failure preserves entries and capacity. Relocation neither copies
  nor destroys element contents.
- `length`, `capacity`, and `deinit` report entry count, report slot count, and
  destroy remaining entries and release storage, respectively.

`for entry in map` borrows `.key: &K` and `.value: &V` for every element type.
`to_ro_entry_iterator` uses that same iterator. `to_rw_entry_iterator` returns
`.key: &K` and `.value: $&V`. Keys remain readonly. `to_key_iterator` and
`to_value_iterator` copy only their selected element, requiring that element to
be implicitly copyable independently of the other type.

Iteration skips deleted slots, invokes no policy operations, allocates nothing,
and has unspecified order. Value edits through references preserve iteration.
Successful insertion, replacement, removal, extraction, growth, and cleanup
invalidate iterators and borrowed entries. Reacquire loans after fallible
mutating calls because safety conservatively joins their possible outcomes.
`next` requires a preceding successful `has_next` and aborts at exhaustion.

Metadata and entries use separate allocations. Only occupied entry slots hold
initialized values; cleanup visits them exactly once. This common representation
supports both copyable and noncopyable elements without a second map family.

`MapQuery#(Map)` supplies the common `Query` for membership, lookup, removal,
and extraction. `MapLookup` returns copies, `MapReferenceLookup` returns readonly
references, and `MutableMapReferenceLookup` returns mutable references while
requiring the readonly lookup capability. None needs a separate text variant.
Map insertion keeps the stored `Key` type and reports allocation failures.

For `HashMap#(String, V, StandardHashPolicy)`, every query operation receives
`StringView`. Looking up a literal or an explicit view neither allocates nor
retains the query. Returned references depend on the table, not the query, and
never expose mutable keys. Borrowed text keys use `HashMap#(.key: StringView, .value: V)` with the same
algorithms and allocation-error handling as other keys.

> [!IDEA]
> A map literal could use a form such as `("a" = 1, "b" = 2)`. Its relationship
> to struct literals, key typing, and allocation needs design.

## Sets

`HashSet#(K, P)` owns keys using the common `HashMap` table, including keys
that cannot be copied. `HashSet#(.key: K)()` uses `StandardHashPolicy` and an
assumed allocator. A supplied `.policy` can infer a custom policy type, just as
for maps. Capacity and allocation errors follow map construction.

`insert(.self, .key, .allocator)` consumes a key and returns an errable Boolean:
true for new membership, false for an equivalent existing key. Duplicate
insertion destroys the supplied key, retains the stored key, and allocates
nothing. Failed growth destroys the supplied key and preserves membership.
`contains` and `remove` receive the policy's `Query`; `extract` transfers a removed
key to the caller. `reserve`, `length`, `capacity`, and `deinit` correspond to map
operations.

`for &key in set` visits readonly references for any key type. `for key in set`
copies keys and requires `ImplicitlyCopyable`. Keys cannot be mutated through
the set. Iterators and returned references follow map structural invalidation;
duplicate insertion and unsuccessful removal preserve them. Borrowed key
contents must remain live and unchanged while stored.

## Graphs

> [!IDEA]
> Add graph collections; their representations and operations remain open.

## Queues

`RingBuffer#(T)` is an owning FIFO queue with a fixed positive capacity. Its
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
- `get_reference(.self, .index)` borrows an occupied element in FIFO order,
  or reports `out_of_bounds`. The buffer implements `Indexable#(RingBuffer#(T))` and
  supports equality search when its elements satisfy that algorithm's contract.
- `deinit(.self)` destroys the remaining occupied elements once
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

## Borrowed bit sets

`BitSetView(.bytes, .count)` borrows initialized mutable byte storage for
`.count` bits and clears the bytes required by that range. Bit zero is the
low bit of the first byte. Insufficient storage reports `out_of_bounds`
before writing anything; size calculation cannot overflow. Storage beyond
the required bytes remains unchanged, and zero bits require no bytes.

`length` reports bit capacity. Checked `contains_bit(.self, .index)` queries a bit;
`set_bit(.self, .index, .value = true)` sets or clears it. Repeated writes are
idempotent, and invalid indices leave storage unchanged. `count_set` counts
only the recorded bit range, ignoring padding bits in the final byte. The
view allocates nothing and retains the backing storage's lifetime.

## Priority queues

`PriorityQueue#(.t: T)(.order = &policy, .capacity = 8)` owns a minimum heap
and infers the policy type. Its allocator can come from `assume`. The same heap
supports copyable and noncopyable elements; all `OrderPolicy` comparisons borrow
operands and must form a stable strict weak order. The policy is borrowed and
must remain live while the queue is used.

`push` consumes its input and grows storage as needed. Allocation failure
destroys that input and preserves existing entries. `peek_reference` returns
`?&T` for any element type; `peek` returns a copy and requires
`ImplicitlyCopyable`. `pop` transfers the minimum element to the caller. All
three return none for an empty heap. Element references follow backing-array
invalidation and refer to heap positions, whose contents can change on push or
pop. `length` reports the number of elements; `deinit` destroys remaining
elements and releases storage.

Peek is constant time; push and pop perform logarithmic comparisons.
Equal-priority removal order is unspecified.

`BitSet(.count, .allocator)` owns initialized storage for a fixed bit count.
It shares the checked `length`, `contains_bit`, `set_bit` and `count_set` operations
with borrowed bit sets. `view(.self: $&BitSet)` borrows a mutable `BitSetView`
without clearing any bits. Cleanup releases the underlying dynamic array and
invalidates its borrowed views; owners cannot be implicitly copied.

`union_with`, `intersect_with` and `difference_with` update an owning bit set
from a readonly `.other` owner without allocating. Both bit counts must match;
`bit_set_size_mismatch` leaves the destination unchanged. Using the same owner
for both operands is valid. Unused high bits remain zero. Union and intersection
with self preserve the set, and difference with self clears it.

Queue supplies Item and the selected pop Result. RingBuffer returns Errable with
empty, while both priority queue families return an optional item. All expose the
result through the same .result label. QueueInsertion selects a collection and
allocation Provider jointly; push uses its Result for full or out_of_memory.
These are scoped contract operations, with no ordinary push/pop overload family.
Provider defaults use lexical allocator lookup. Owning inputs move into lexical
owners before fallible insertion, retaining cleanup on rejection and allocation
failure. Dynamic-array reservation keeps that static Provider through allocation.
