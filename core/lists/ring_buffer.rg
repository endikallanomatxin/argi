_RingBufferShape := (.marker: UInt8)

implement Deinit#(_RingBufferShape) (
    .deinit = (.self: $&_RingBufferShape) -> () {
    }
)

-- The live interval has _length slots starting at _head, modulo _capacity.
-- All other slots are vacant. Only this owner changes occupancy; raw slot
-- handles and physical indices never escape through the public API.
RingBuffer := #(.t: Type) (
    ._allocation : Allocation
    ._capacity   : UIntNative
    ._head       : UIntNative
    ._length     : UIntNative
    ._shape      : _RingBufferShape
)

RingBufferInitArgs: Type = #(.t: Type, .Provider: Type: Allocator) (
    .capacity  : UIntNative,
    .allocator : $&Provider
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.t: Type, .Provider: Type: Allocator) Init#(
    RingBuffer#(.t: t), RingBufferInitArgs#(t, Provider)
) (
    .Result : Type = Errable#(RingBuffer#(.t: t), (..invalid_capacity, ..out_of_memory))

    .init = RingBufferInitArgs#(t, Provider) -> (.result: Result) {
        assume error_tracer

        _init_capacity ::= capacity
        _init_allocator ::= allocator

        constructed :: RingBuffer#(.t: t)

        if _init_capacity == 0 {
            result = ..error(.reason = ..invalid_capacity)
            return
        }

        allocation ::= allocate#(.t: t)(_init_allocator, .count = _init_capacity)!
        constructed = (
            ._allocation = ~allocation
            ._capacity   = _init_capacity
            ._head       = 0
            ._length     = 0
            ._shape      = (.marker = 0)
        )

        result = ..ok ~constructed
    }
)

_collection_capacity_ring_buffer := #(.t: Type) (.self: &RingBuffer#(.t: t)) -> (
    .count : UIntNative
) {
    count = self&._capacity
}

implement#(.t: Type) CollectionCapacity#(RingBuffer#(.t: t)) (
    .measure_capacity = _collection_capacity_ring_buffer
)

_ring_buffer_physical_index := #(.t: Type) (.self: &RingBuffer#(.t: t), .index: UIntNative) -> (
    .physical : UIntNative
) {
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

_invalidate_ring_buffer_shape := #(.t: Type) (.self: $&RingBuffer#(.t: t)) -> () {
    shape ::= $&self&._shape
    deinit(.self = shape)
    shape&= (.marker = 0)
}

_ring_buffer_occupied_pointer := #(.t: Type) (.self: &RingBuffer#(.t: t), .index: UIntNative) -> (
    .pointer : $&t
) {
    if index >= self&._length { abort }
    physical ::= _ring_buffer_physical_index(self, .index = index).physical
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = physical)
    slot_index: ?UIntNative = ..some(.value = slot._index)
    pointer = trusted_establish_allocation_slot#(.t: t)(
        .allocation = &self&._allocation
        .slot       = slot._raw
        .anchor     = self&._allocation.anchor
        .index      = slot_index
    ).reference
}

_queue_push_ring_buffer := #(.t: Type, .Provider: Type: Allocator) (
    .self         : $&RingBuffer#(.t: t),
    .value        : t,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..full))) {
    assume error_tracer

    assume allocator
    owned ::= ~value

    if self&._length == self&._capacity {
        result = ..error(.reason = ..full)
        return
    }

    physical ::= _ring_buffer_physical_index(self, .index = self&._length).physical
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = physical)
    _trusted_uninit_write#(.t: t)(
        .allocation = $&self&._allocation, .slot = slot, .value = ~owned
    )
    _invalidate_ring_buffer_shape(self)
    self&._length = self&._length + 1

    result = ..ok Void()
}

_queue_pop_ring_buffer := #(.t: Type) (
    .self: $&RingBuffer#(.t: t), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(t, (..empty))) {
    assume error_tracer

    if self&._length == 0 {
        result = ..error(.reason = ..empty)
        return
    }

    slot ::= _trusted_uninit_slot#(.t: t)(
        .allocation = &self&._allocation, .index = self&._head
    )
    value ::= _trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = slot)
    _invalidate_ring_buffer_shape(self)
    self&._length = self&._length - 1
    self&._head = self&._head + 1

    if self&._head == self&._capacity { self&._head = 0 }

    result = ..ok ~value
}

implement#(.t: Type) Deinit#(RingBuffer#(.t: t)) (
    .deinit = (.self: $&RingBuffer#(.t: t)) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        while self&._length > 0 {
            discarded ::= ~unwrap_or_abort(.value = pop(self))
        }

        trusted_opaque_mark_empty(.storage = $&self&._allocation)
        deinit(.self = $&self&._allocation)
    }
)

implement#(.t: Type) Indexable#(RingBuffer#(.t: t)) (
    .Item : Type = t

    .length = (.self: &RingBuffer#(.t: t)) -> (.count: UIntNative) { count = self&._length }

    .get_reference = (
        .self: &RingBuffer#(.t: t), .index: UIntNative, .error_tracer: $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(&t, (..out_of_bounds))) {
        assume error_tracer

        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        mutable ::= _ring_buffer_occupied_pointer(self, .index = index).pointer
        reference ::= read_reference#(.t: t)(.base = mutable).reference
        borrowed ::= depend_on#(.t: &t)(
            .value = reference
            .on    = erase_reference#(.t: _RingBufferShape)(.base = &self&._shape).reference
        ).result

        result = ..ok borrowed
    }
)

implement#(.t: Type) Queue#(RingBuffer#(.t: t)) (
    .Item   : Type = t
    .Result : Type = Errable#(t, (..empty))
    .pop    = _queue_pop_ring_buffer
)

implement#(.t: Type, .Provider: Type: Allocator) QueueInsertion#(RingBuffer#(.t: t), Provider) (
    .Result : Type = Errable#(Void, (..full))
    .push   = _queue_push_ring_buffer
)
