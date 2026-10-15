-- The initialized interval shrinks from the front without relocating values.
-- Slots outside [_next, _end) are vacant and are never read or destroyed.
DynamicArrayMovingIterator#(.t: Type): Type = (
    ._allocation : Allocation,
    ._next       : UIntNative,
    ._end        : UIntNative
)

implement#(.t: Type) Deinit#(DynamicArrayMovingIterator#(.t: t)) (
    .deinit = (.self: $&DynamicArrayMovingIterator#(.t: t)) -> () {
        while self&._next < self&._end {
            discarded ::= ~next(self).value
        }

        trusted_opaque_mark_empty(.storage = $&self&._allocation)
        deinit(.self = $&self&._allocation)
    }
)

DequeMovingIterator#(.t: Type): Type = (._owner: Deque#(.t: t))

implement#(.t: Type) Deinit#(DequeMovingIterator#(.t: t)) (
    .deinit = (.self: $&DequeMovingIterator#(.t: t)) -> () {
        while has_next(self).ok {
            discarded ::= ~next(self).value
        }

        deinit(.self = $&self&._owner)
    }
)

implement#(.t: Type) MovingIterable#(DynamicArray#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = DynamicArrayMovingIterator#(.t: t)

    .to_moving_iterator = (.value: DynamicArray#(.t: t)) -> (
        .iterator : DynamicArrayMovingIterator#(.t: t)
    ) {
        count ::= value._length
        value._length = 0
        iterator = (._allocation = ~value._allocation, ._next = 0, ._end = count)
    }
)

implement#(.t: Type) Iterator#(DynamicArrayMovingIterator#(.t: t)) (
    .Item : Type = t

    .has_next = (.self: &DynamicArrayMovingIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._next < self&._end
    }

    .next = (.self: $&DynamicArrayMovingIterator#(.t: t)) -> (.value: t) {
        if self&._next == self&._end { abort }
        slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation, .index = self&._next
        )
        value = ~_trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = slot)
        self&._next = self&._next + 1
    }
)

implement#(.t: Type) MovingIterable#(Deque#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = DequeMovingIterator#(.t: t)

    .to_moving_iterator = (.value: Deque#(.t: t)) -> (.iterator: DequeMovingIterator#(.t: t)) {
        iterator = (._owner = ~value)
    }
)

implement#(.t: Type) Iterator#(DequeMovingIterator#(.t: t)) (
    .Item : Type = t

    .has_next = (.self: &DequeMovingIterator#(.t: t)) -> (.ok: Bool) {
        ok = length(&self&._owner).count != 0
    }

    .next = (.self: $&DequeMovingIterator#(.t: t)) -> (.value: t) {
        ring ::= $&self&._owner._ring

        if ring&._length == 0 { abort }
        slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &ring&._allocation, .index = ring&._head
        )
        value = ~_trusted_uninit_take#(.t: t)(.allocation = $&ring&._allocation, .slot = slot)
        _invalidate_ring_buffer_shape(ring)
        ring&._length = ring&._length - 1
        ring&._head = ring&._head + 1

        if ring&._head == ring&._capacity { ring&._head = 0 }
    }
)
