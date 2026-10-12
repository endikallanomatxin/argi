-- Iterators retain both the owner and the shape generation at creation.
DequeIterator#(.t: Type): Type = (._owner: &Deque#(.t: t), ._index: UIntNative)

DequeROPointerIterator#(.t: Type): Type = (._owner: &Deque#(.t: t), ._index: UIntNative)

DequeRWPointerIterator#(.t: Type): Type = (._owner: $&Deque#(.t: t), ._index: UIntNative)

implement#(
        .t : Type: ImplicitlyCopyable
    ) Iterable#(Deque#(.t: t)) (
    .Item: Type = t
    .IteratorType: Type = DequeIterator#(.t: t)

    .to_iterator = (
            .value : &Deque#(.t: t)
        ) -> (
            .iterator : DequeIterator#(.t: t)
        ) {
        owner ::= depend_on#(.t: &Deque#(.t: t))(
            .value = value
            .on    = erase_reference#(.t: _RingBufferShape)(.base = &value&._ring._shape).reference
        ).result
        iterator = (._owner = owner, ._index = 0)
    }
)

implement#(.t: Type: ImplicitlyCopyable) Iterator#(DequeIterator#(.t: t)) (
    .Item: Type = t

    .has_next = (.self: &DequeIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(self&._owner).count
    }

    .next = (.self: $&DequeIterator#(.t: t)) -> (.value: t) {
        current ::= self&._index
        pointer ::= _ring_buffer_occupied_pointer(&self&._owner&._ring, .index = current).pointer
        value = pointer&
        self&._index = current + 1
    }
)

implement#(
        .t : Type
    ) ROPointerIterable#(Deque#(.t: t)) (
    .Item: Type = t
    .IteratorType: Type = DequeROPointerIterator#(.t: t)

    .to_ro_pointer_iterator = (
            .value : &Deque#(.t: t)
        ) -> (
            .iterator : DequeROPointerIterator#(.t: t)
        ) {
        owner ::= depend_on#(.t: &Deque#(.t: t))(
            .value = value
            .on    = erase_reference#(.t: _RingBufferShape)(.base = &value&._ring._shape).reference
        ).result
        iterator = (._owner = owner, ._index = 0)
    }
)

implement#(.t: Type) Iterator#(DequeROPointerIterator#(.t: t)) (
    .Item: Type = &t

    .has_next = (.self: &DequeROPointerIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(self&._owner).count
    }

    .next = (.self: $&DequeROPointerIterator#(.t: t)) -> (.value: &t) {
        current ::= self&._index
        pointer ::= _ring_buffer_occupied_pointer(&self&._owner&._ring, .index = current).pointer
        readonly ::= read_reference#(.t: t)(.base = pointer).reference
        value = depend_on#(.t: &t)(
            .value = readonly
            .on    = erase_reference#(.t: _RingBufferShape)(.base = &self&._owner&._ring._shape).reference
        ).result
        self&._index = current + 1
    }
)

implement#(
        .t : Type
    ) RWPointerIterable#(Deque#(.t: t)) (
    .Item: Type = t
    .IteratorType: Type = DequeRWPointerIterator#(.t: t)

    .to_rw_pointer_iterator = (
            .value : $&Deque#(.t: t)
        ) -> (
            .iterator : DequeRWPointerIterator#(.t: t)
        ) {
        owner ::= depend_on#(.t: $&Deque#(.t: t))(
            .value = value
            .on    = erase_reference#(.t: _RingBufferShape)(.base = &value&._ring._shape).reference
        ).result
        iterator = (._owner = owner, ._index = 0)
    }
)

implement#(.t: Type) Iterator#(DequeRWPointerIterator#(.t: t)) (
    .Item: Type = $&t

    .has_next = (.self: &DequeRWPointerIterator#(.t: t)) -> (.ok: Bool) {
        ok = self&._index < length(self&._owner).count
    }

    .next = (.self: $&DequeRWPointerIterator#(.t: t)) -> (.value: $&t) {
        current ::= self&._index
        pointer ::= _ring_buffer_occupied_pointer(&self&._owner&._ring, .index = current).pointer
        value = depend_on#(.t: $&t)(
            .value = pointer
            .on    = erase_reference#(.t: _RingBufferShape)(.base = &self&._owner&._ring._shape).reference
        ).result
        self&._index = current + 1
    }
)
