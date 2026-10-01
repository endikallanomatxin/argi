# Other collections

The library may offer maps, sets, graphs, queues, and iterator helpers in
addition to the [list families](161_lists.md). Accepted contracts are described
below; exploratory collections are marked as ideas.

## Maps

> [!IDEA]
> A map literal could use a form such as `("a" = 1, "b" = 2)`. Its relationship
> to struct literals, key typing, and allocation needs design.

## Sets

> [!IDEA]
> Add a set collection; its representation and operations remain open.

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

> [!IDEA]
> A growable `Deque<T>` could add double-ended insertion and removal. Its
> front position, length, capacity, growth failures, and owning-element
> relocation need a concrete use case before fixing the API.

## SoA and AoS

> [!IDEA]
> Explore struct-of-arrays and array-of-structs layouts for collections with
> different access patterns. Their shape and selection rules remain open.

## Iterator helpers

> [!IDEA]
> Beyond the basic [iterator contract](44_control_flow.md), library adapters
> could provide zipping, enumeration, and sliding-window iteration.
