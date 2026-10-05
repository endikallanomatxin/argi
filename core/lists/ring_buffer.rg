_RingBufferShape: Type = (.marker: UInt8)

_RingBufferShape deinit(.self: $&_RingBufferShape) -> () := {}

-- The live interval has _length slots starting at _head, modulo _capacity.
-- All other slots are vacant. Only this owner changes occupancy; raw slot
-- handles and physical indices never escape through the public API.
RingBuffer#(.t: Type): Type = (
    ._allocation : Allocation
    ._capacity   : UIntNative
    ._head       : UIntNative
    ._length     : UIntNative
    ._shape      : _RingBufferShape
)

RingBuffer init#(
        .t : Type
    )(
        .capacity  : UIntNative,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(.t: RingBuffer#(.t: t), .reasons: (..invalid_capacity, ..out_of_memory))
    ) := {
    constructed :: RingBuffer#(.t: t)

    if capacity == 0 {
        result = ..error(.reason = ..invalid_capacity)
        return
    }

    element_size ::= size_of(.type = t)
    maximum ::= integer_limits(.value = capacity).maximum

    if element_size != 0 and capacity > maximum / element_size {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    allocation ::= allocate#(.t: t)(.self = allocator, .count = capacity)!
    constructed = (
        ._allocation = ~allocation
        ._capacity   = capacity
        ._head       = 0
        ._length     = 0
        ._shape      = (.marker = 0)
    )

    result = ..ok ~constructed
}

length#(.t: Type)(.self: &RingBuffer#(.t: t)) -> (.count: UIntNative) := { count = self&._length }

capacity#(.t: Type)(.self: &RingBuffer#(.t: t)) -> (.count: UIntNative) := {
    count = self&._capacity
}

_ring_buffer_physical_index#(
        .t : Type
    )(
        .self  : &RingBuffer#(.t: t),
        .index : UIntNative
    ) -> (
        .physical : UIntNative
    ) := {
    if index >= self&._capacity { abort }
    -- Subtract before adding: head + index could overflow even when the
    -- wrapped physical index belongs to the allocation.
    remaining ::= self&._capacity - self&._head

    if index < remaining {
        physical = self&._head + index
    } else {
        physical = index - remaining
    }
}

_invalidate_ring_buffer_shape#(.t: Type)(.self: $&RingBuffer#(.t: t)) -> () := {
    shape ::= $&self&._shape
    deinit(.self = shape)
    shape&= (.marker = 0)
}

_ring_buffer_occupied_pointer#(
        .t : Type
    )(
        .self  : &RingBuffer#(.t: t),
        .index : UIntNative
    ) -> (
        .pointer : $&t
    ) := {
    if index >= self&._length { abort }
    physical ::= _ring_buffer_physical_index(.self = self, .index = index).physical
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = physical)
    pointer = trusted_establish_allocation_slot#(.t: t)(
        .allocation = &self&._allocation
        .slot       = slot._raw
        .anchor     = self&._allocation.anchor
    ).reference
}

get_ro_ref#(
        .t : Type
    )(
        .self  : &RingBuffer#(.t: t),
        .index : UIntNative
    ) -> (
        .result : Errable#(.t: &t, .reasons: (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    mutable ::= _ring_buffer_occupied_pointer(.self = self, .index = index).pointer
    reference ::= read_reference#(.t: t)(.base = mutable).reference
    borrowed ::= depend_on#(.t: &t)(
        .value = reference
        .on    = erase_reference#(.t: _RingBufferShape)(.base = &self&._shape).reference
    ).result

    result = ..ok borrowed
}

RingBuffer#(.t: Type) implements Indexable#(.t: t)

push#(
        .t : Type
    )(
        .self      : $&RingBuffer#(.t: t),
        .value     : t,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..full))
    ) := {
    assume allocator
    owned ::= ~value

    if self&._length == self&._capacity {
        result = ..error(.reason = ..full)
        return
    }

    physical ::= _ring_buffer_physical_index(.self = self, .index = self&._length).physical
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = physical)
    _trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = slot, .value = ~owned)
    _invalidate_ring_buffer_shape(.self = self)
    self&._length = self&._length + 1

    result = ..ok Void()
}

pop#(.t: Type)(.self: $&RingBuffer#(.t: t)) -> (.result: Errable#(.t: t, .reasons: (..empty))) := {
    if self&._length == 0 {
        result = ..error(.reason = ..empty)
        return
    }

    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = self&._head)
    value ::= _trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = slot)
    _invalidate_ring_buffer_shape(.self = self)
    self&._length = self&._length - 1
    self&._head = self&._head + 1

    if self&._head == self&._capacity { self&._head = 0 }

    result = ..ok ~value
}

RingBuffer deinit#(.t: Type)(.self: $&RingBuffer#(.t: t), .allocator: $&Allocator) -> () := {
    assume allocator

    while self&._length > 0 {
        discarded ::= ~unwrap_or_abort(.value = pop(.self = self))
    }

    trusted_opaque_mark_empty(.storage = $&self&._allocation)
    deinit(.self = $&self&._allocation)
}
