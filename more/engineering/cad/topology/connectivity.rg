-- Transient inverse of next. Physical array order does not define adjacency.
-- No persistent prev field or per-halfedge allocation is needed.
_topology_predecessors := (
    .topology: &Topology, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(DynamicArray#(UIntNative), BuildErrors)) {
    count ::= length(&topology&._halfedges).count
    previous ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = count)!
    i :: UIntNative = 0
    while i < count {
        push_assume_capacity($&previous, .value = count)
        i = i + 1
    }
    i = 0
    while i < count {
        item ::= get(&topology&._halfedges, .index = i)!
        next ::= item.next | convert#(.to: UIntNative)(_)
        successor ::= get(&topology&._halfedges, .index = next)!
        slot ::= get_mutable_reference($&previous, .index = next)!
        if slot&!= count or successor.loop != item.loop {
            result = ..error(.reason = ..inconsistent_orientation)
            return
        }
        slot&= i
        i = i + 1
    }
    result = ..ok ~previous
}
