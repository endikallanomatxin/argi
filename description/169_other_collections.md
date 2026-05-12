## Maps

## Sets

## Graphs

## Queues

### RingBuffer (circular, fijo o dinámico)
Para colas, audio, telemetría.
RingBuffer#(.t) = (.ptr:&t, .cap:Int, .head:Int, .tail:Int)

### Deque (doble extremo, dinámico)
Generaliza ring buffer con crecimiento.
Deque#(.t) = (.ptr:&t, .len:Int, .cap:Int, .front:Int, .alloc:&Allocator)


---

More info on collection types in `../library/collections/`

---

### SoA / AoS

> [!TODO]

---

### Iterators

- basic iterator
- zipping iterator
- enumerating iterator
- sliding window iterator

