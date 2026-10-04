-- Iterators retain both the owner and the shape generation at creation.
DequeIterator#(.t: Type): Type = (._owner: &Deque#(.t: t), ._index: UIntNative)

DequeIterator#(.t: Type: ImplicitlyCopyable) implements Iterator#(.t: t)
Deque#(.t: Type: ImplicitlyCopyable) implements Iterable#(.t: t)

to_iterator#(
        .t : Type: ImplicitlyCopyable
    )(
        .value : &Deque#(.t: t)
    ) -> (
        .iterator : DequeIterator#(.t: t)
    ) := {
    owner ::= depend_on#(.t: &Deque#(.t: t))(
        .value = value
        .on    = erase_reference#(.t: _RingBufferShape)(.base = &value&._ring._shape).reference
    ).result
    iterator = (._owner = owner, ._index = 0)
}

has_next#(.t: Type: ImplicitlyCopyable)(.self: &DequeIterator#(.t: t)) -> (.ok: Bool) := {
    ok = self&._index < length(.self = self&._owner).count
}

next#(.t: Type: ImplicitlyCopyable)(.self: $&DequeIterator#(.t: t)) -> (.value: t) := {
    current ::= self&._index
    pointer ::= _ring_buffer_occupied_pointer(.self = &self&._owner&._ring, .index = current).pointer
    value = pointer&
    self&._index = current + 1
}

DequeROPointerIterator#(.t: Type): Type = (._owner: &Deque#(.t: t), ._index: UIntNative)

DequeROPointerIterator#(.t: Type) implements Iterator#(.t: &t)
Deque#(.t: Type) implements ROPointerIterable#(.t: t)

to_ro_pointer_iterator#(
        .t : Type
    )(
        .value : &Deque#(.t: t)
    ) -> (
        .iterator : DequeROPointerIterator#(.t: t)
    ) := {
    owner ::= depend_on#(.t: &Deque#(.t: t))(
        .value = value
        .on    = erase_reference#(.t: _RingBufferShape)(.base = &value&._ring._shape).reference
    ).result
    iterator = (._owner = owner, ._index = 0)
}

has_next#(.t: Type)(.self: &DequeROPointerIterator#(.t: t)) -> (.ok: Bool) := {
    ok = self&._index < length(.self = self&._owner).count
}

next#(.t: Type)(.self: $&DequeROPointerIterator#(.t: t)) -> (.value: &t) := {
    current ::= self&._index
    pointer ::= _ring_buffer_occupied_pointer(.self = &self&._owner&._ring, .index = current).pointer
    readonly ::= read_reference#(.t: t)(.base = pointer).reference
    value = depend_on#(.t: &t)(
        .value = readonly
        .on    = erase_reference#(.t: _RingBufferShape)(.base = &self&._owner&._ring._shape).reference
    ).result
    self&._index = current + 1
}

DequeRWPointerIterator#(.t: Type): Type = (._owner: $&Deque#(.t: t), ._index: UIntNative)

DequeRWPointerIterator#(.t: Type) implements Iterator#(.t: $&t)
Deque#(.t: Type) implements RWPointerIterable#(.t: t)

to_rw_pointer_iterator#(
        .t : Type
    )(
        .value : $&Deque#(.t: t)
    ) -> (
        .iterator : DequeRWPointerIterator#(.t: t)
    ) := {
    owner ::= depend_on#(.t: $&Deque#(.t: t))(
        .value = value
        .on    = erase_reference#(.t: _RingBufferShape)(.base = &value&._ring._shape).reference
    ).result
    iterator = (._owner = owner, ._index = 0)
}

has_next#(.t: Type)(.self: &DequeRWPointerIterator#(.t: t)) -> (.ok: Bool) := {
    ok = self&._index < length(.self = self&._owner).count
}

next#(.t: Type)(.self: $&DequeRWPointerIterator#(.t: t)) -> (.value: $&t) := {
    current ::= self&._index
    pointer ::= _ring_buffer_occupied_pointer(.self = &self&._owner&._ring, .index = current).pointer
    value = depend_on#(.t: $&t)(
        .value = pointer
        .on    = erase_reference#(.t: _RingBufferShape)(.base = &self&._owner&._ring._shape).reference
    ).result
    self&._index = current + 1
}
