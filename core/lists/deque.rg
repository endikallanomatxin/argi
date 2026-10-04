-- A growable owner over the ring's live-slot invariant. Growth linearizes
-- logical order into new storage and moves every element exactly once.
Deque#(.t: Type): Type = (._ring: RingBuffer#(.t: t))

Deque init#(
        .t : Type
    )(
        .capacity  : UIntNative  = 8,
        .allocator : $&Allocator = reach allocator,
    ) -> (
        .result : Errable#(.t: Deque#(.t: t), .reasons: (..out_of_memory))
    ) := {
    actual :: UIntNative = capacity
    if actual == 0 { actual = 1 }
    match RingBuffer#(.t: t)(.capacity = actual, .allocator = allocator) {
        ..ok ~ring { result = ..ok(._ring = ~ring) }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

length#(.t: Type)(.self: &Deque#(.t: t)) -> (.count: UIntNative) := {
    count = self&._ring._length
}

capacity#(.t: Type)(.self: &Deque#(.t: t)) -> (.count: UIntNative) := {
    count = self&._ring._capacity
}

reserve#(
        .t : Type
    )(
        .self      : $&Deque#(.t: t),
        .capacity  : UIntNative,
        .allocator : $&Allocator      = reach allocator,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_memory))
    ) := {
    if capacity <= self&._ring._capacity {
        result = ..ok Void()
        return
    }
    element_size ::= size_of(.type = t)
    bytes ::= capacity * element_size
    if element_size != 0 and bytes / element_size != capacity {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    new_allocation ::= allocate#(.t: t)(.self = allocator, .count = capacity)!
    index :: UIntNative = 0
    while index < self&._ring._length {
        physical ::= _ring_buffer_physical_index(.self = &self&._ring, .index = index).physical
        old_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._ring._allocation
            .index      = physical
        )
        new_slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &new_allocation, .index = index)
        _trusted_uninit_relocate#(.t: t)(
            .source_allocation      = &self&._ring._allocation
            .source                 = old_slot
            .destination_allocation = &new_allocation
            .destination            = new_slot
        )
        index = index + 1
    }
    deinit(.self = $&self&._ring._allocation)
    _invalidate_ring_buffer_shape(.self = $&self&._ring)
    self&._ring = (
        ._allocation = ~new_allocation
        ._capacity   = capacity
        ._head       = 0
        ._length     = self&._ring._length
        ._shape      = (.marker = 0)
    )
    result = ..ok Void()
}

_deque_ensure_room#(
        .t : Type
    )(
        .self      : $&Deque#(.t: t),
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_memory))
    ) := {
    if self&._ring._length < self&._ring._capacity {
        result = ..ok Void()
        return
    }
    grown ::= self&._ring._capacity * 2
    if grown <= self&._ring._capacity {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    result = reserve(.self = self, .capacity = grown, .allocator = allocator)
}

push_back#(
        .t : Type
    )(
        .self      : $&Deque#(.t: t),
        .value     : t,
        .allocator : $&Allocator      = reach allocator,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_memory))
    ) := {
    match _deque_ensure_room(.self = self, .allocator = allocator) {
        ..error _ {
            -- Insertion consumes the argument on failure too. The deque's
            -- old occupancy and storage remain unchanged when growth fails.
            trusted_opaque_drop(.slot = $&value, .allocator = allocator)
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok _ {}
    }
    unwrap_or_abort(.value = push(.self = $&self&._ring, .value = ~value, .allocator = allocator))
    result = ..ok Void()
}

push_front#(
        .t : Type
    )(
        .self      : $&Deque#(.t: t),
        .value     : t,
        .allocator : $&Allocator      = reach allocator,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_memory))
    ) := {
    match _deque_ensure_room(.self = self, .allocator = allocator) {
        ..error _ {
            trusted_opaque_drop(.slot = $&value, .allocator = allocator)
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok _ {}
    }
    head :: UIntNative = self&._ring._head
    if head == 0 { head = self&._ring._capacity }
    head = head - 1
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._ring._allocation, .index = head)
    _trusted_uninit_write#(.t: t)(
        .allocation = $&self&._ring._allocation
        .slot       = slot
        .value      = ~value
    )
    _invalidate_ring_buffer_shape(.self = $&self&._ring)
    self&._ring._head = head
    self&._ring._length = self&._ring._length + 1
    result = ..ok Void()
}

pop_front#(.t: Type)(.self: $&Deque#(.t: t)) -> (.result: Errable#(.t: t, .reasons: (..empty))) := {
    result = pop(.self = $&self&._ring)
}

pop_back#(.t: Type)(.self: $&Deque#(.t: t)) -> (.result: Errable#(.t: t, .reasons: (..empty))) := {
    if self&._ring._length == 0 {
        result = ..error(.reason = ..empty)
        return
    }
    index ::= self&._ring._length - 1
    physical ::= _ring_buffer_physical_index(.self = &self&._ring, .index = index).physical
    slot ::= _trusted_uninit_slot#(.t: t)(
        .allocation = &self&._ring._allocation
        .index      = physical
    )
    moved ::= _trusted_uninit_take#(.t: t)(.allocation = $&self&._ring._allocation, .slot = slot)
    _invalidate_ring_buffer_shape(.self = $&self&._ring)
    self&._ring._length = index
    result = ..ok ~moved
}

get_ro_ref#(
        .t : Type
    )(
        .self  : &Deque#(.t: t),
        .index : UIntNative
    ) -> (
        .result : Errable#(.t: &t, .reasons: (..out_of_bounds))
    ) := {
    result = get_ro_ref(.self = &self&._ring, .index = index)
}

get_rw_ref#(
        .t : Type
    )(
        .self  : $&Deque#(.t: t),
        .index : UIntNative
    ) -> (
        .result : Errable#(.t: $&t, .reasons: (..out_of_bounds))
    ) := {
    if index >= self&._ring._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    pointer ::= _ring_buffer_occupied_pointer(.self = &self&._ring, .index = index).pointer
    result = ..ok depend_on#(.t: $&t)(
        .value = pointer
        .on    = erase_reference#(.t: _RingBufferShape)(.base = &self&._ring._shape).reference
    ).result
}

get#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : &Deque#(.t: t),
        .index : UIntNative
    ) -> (
        .result : Errable#(.t: t, .reasons: (..out_of_bounds))
    ) := {
    pointer ::= get_ro_ref(.self = self, .index = index)!
    result = ..ok pointer&
}

Deque#(.t: Type) implements Indexable#(.t: t)

Deque deinit#(.t: Type)(.self: $&Deque#(.t: t), .allocator: $&Allocator = reach allocator) -> () := {
    deinit(.self = $&self&._ring, .allocator = allocator)
}
