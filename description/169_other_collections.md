## Maps

## Sets

## Graphs

## Queues

### RingBuffer (circular, fixed or dynamic)
For queues, audio, and telemetry.
RingBuffer#(.t) = (.ptr:&t, .cap:Int, .head:Int, .tail:Int)

### Deque (double-ended, dynamic)
Generalizes a ring buffer with growth.
Deque#(.t) = (.ptr:&t, .len:Int, .cap:Int, .front:Int, .alloc:&Allocator)


---

More info on collection types in `../library/collections/`

---

### SoA / AoS

> [!IDEA]
> The shape of SoA and AoS collections remains exploratory.

---

### Iterators

- basic iterator
- zipping iterator
- enumerating iterator
- sliding window iterator
