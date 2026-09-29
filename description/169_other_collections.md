# Other collections

The library may offer maps, sets, graphs, queues, and iterator helpers in
addition to the [list families](161_lists.md). The following shapes and APIs
are exploratory.

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

> [!IDEA]
> `RingBuffer#(.t)` could be a circular buffer with fixed or dynamic capacity
> for queues, audio, and telemetry. A possible representation has storage,
> capacity, and head and tail positions.
>
> A growable `Deque#(.t)` could add double-ended insertion and removal, with
> a front position, length, capacity, and allocator. These are sketches of the
> data each type might need, not fixed layouts or APIs.
>
> ```rg
> RingBuffer#(.t) = (.ptr: &t, .cap: Int, .head: Int, .tail: Int)
> Deque#(.t) = (.ptr: &t, .len: Int, .cap: Int, .front: Int,
>               .alloc: &Allocator)
> ```

## SoA and AoS

> [!IDEA]
> Explore struct-of-arrays and array-of-structs layouts for collections with
> different access patterns. Their shape and selection rules remain open.

## Iterator helpers

> [!IDEA]
> Beyond the basic [iterator contract](44_control_flow.md), library adapters
> could provide zipping, enumeration, and sliding-window iteration.
