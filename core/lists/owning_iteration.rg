-- The initialized interval shrinks from the front without relocating values.
-- Slots outside [_next, _end) are vacant and are never read or destroyed.
DynamicArrayOwningIterator#(.t: Type): Type = (
    ._allocation : Allocation,
    ._next       : UIntNative,
    ._end        : UIntNative
)

DynamicArray#(.t: Type) implements OwningIterable#(.t: t)
DynamicArrayOwningIterator#(.t: Type) implements Iterator#(.t: t)

to_owning_iterator#(
        .t : Type
    )(
        .value : DynamicArray#(.t: t)
    ) -> (
        .iterator : DynamicArrayOwningIterator#(.t: t)
    ) := {
    count ::= value._length
    value._length = 0
    iterator = (._allocation = ~value._allocation, ._next = 0, ._end = count)
}

has_next#(.t: Type)(.self: &DynamicArrayOwningIterator#(.t: t)) -> (.ok: Bool) := {
    ok = self&._next < self&._end
}

next#(.t: Type)(.self: $&DynamicArrayOwningIterator#(.t: t)) -> (.value: t) := {
    if self&._next == self&._end { abort }
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = self&._next)
    value = ~_trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = slot)
    self&._next = self&._next + 1
}

DynamicArrayOwningIterator deinit#(
        .t : Type
    )(
        .self      : $&DynamicArrayOwningIterator#(.t: t),
        .allocator : $&Allocator
    ) -> () := {
    assume allocator

    while self&._next < self&._end {
        discarded ::= ~next(self).value
    }

    trusted_opaque_mark_empty(.storage = $&self&._allocation)
    deinit(.self = $&self&._allocation)
}

DequeOwningIterator#(.t: Type): Type = (._owner: Deque#(.t: t))

Deque#(.t: Type) implements OwningIterable#(.t: t)
DequeOwningIterator#(.t: Type) implements Iterator#(.t: t)

to_owning_iterator#(.t: Type)(.value: Deque#(.t: t)) -> (.iterator: DequeOwningIterator#(.t: t)) := {
    iterator = (._owner = ~value)
}

has_next#(.t: Type)(.self: &DequeOwningIterator#(.t: t)) -> (.ok: Bool) := {
    ok = length(&self&._owner).count != 0
}

next#(.t: Type)(.self: $&DequeOwningIterator#(.t: t)) -> (.value: t) := {
    ring ::= $&self&._owner._ring

    if ring&._length == 0 { abort }
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &ring&._allocation, .index = ring&._head)
    value = ~_trusted_uninit_take#(.t: t)(.allocation = $&ring&._allocation, .slot = slot)
    _invalidate_ring_buffer_shape(ring)
    ring&._length = ring&._length - 1
    ring&._head = ring&._head + 1

    if ring&._head == ring&._capacity { ring&._head = 0 }
}

DequeOwningIterator deinit#(
        .t : Type
    )(
        .self      : $&DequeOwningIterator#(.t: t),
        .allocator : $&Allocator
    ) -> () := {
    assume allocator

    while has_next(self).ok {
        discarded ::= ~next(self).value
    }

    deinit(.self = $&self&._owner, .allocator = allocator)
}
