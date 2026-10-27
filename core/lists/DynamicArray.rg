-- A shape generation gives borrowed views an invalidation
-- boundary independent of allocation roots. Structural changes renew it;
-- replacing an element's value without changing shape does not.
_DynamicArrayShape := (.marker: UInt8)

implement Deinit#(_DynamicArrayShape) (
    .deinit = (.self: $&_DynamicArrayShape) -> () {
    }
)

DynamicArray := #(.t: Type) (
    --
    -- Canonical contiguous owning dynamic list.
    --
    -- It owns heap memory through `Allocation` and should serve as the default
    -- resizable list shape in `core`.
    --
    -- Storage operations own, move, relocate, and destroy elements without
    -- requiring any copy capability from `t`. Value reads and whole-array
    -- copies are separate conditional capabilities.
    --
    ._allocation : Allocation
    -- `length` is the runtime opaque-slot invariant: indices below it contain
    -- exactly one live value; the rest are vacant MaybeUninit<t> slots. The
    -- handles are formed only when operating on a slot, so no per-slot state
    -- is stored alongside the allocation.
    ._length   : UIntNative
    ._capacity : UIntNative
    ._shape    : _DynamicArrayShape
)

_collection_capacity_DynamicArray := #(.t: Type) (.self: &DynamicArray#(.t: t)) -> (
    .count : UIntNative
) {
    count = self&._capacity
}

implement#(.t: Type) CollectionCapacity#(DynamicArray#(.t: t)) (
    .measure_capacity = _collection_capacity_DynamicArray
)

-- An owner that has consumed every element may need to expose the empty
-- opaque storage state to the safety checker before ending a temporal root.
_trusted_dynamic_array_mark_empty := #(.t: Type) (.self: $&DynamicArray#(.t: t)) -> () {
    if self&._length != 0 { abort }
    trusted_opaque_mark_empty(.storage = $&self&._allocation)
}

DynamicArrayInitArgs: Type = #(.t: Type, .A: Type: Allocator) (
    .allocator : $&A        = reach allocator,
    .capacity  : UIntNative = 0
)

implement#(.t: Type, .A: Type: Allocator) Init#(DynamicArray#(t), DynamicArrayInitArgs#(t, A)) (
    .Result : Type = Errable#(DynamicArray#(t), (..out_of_memory))

    .init = DynamicArrayInitArgs#(t, A) -> (.result: Result) {
        _init_allocator ::= allocator
        _init_capacity ::= capacity

        constructed :: DynamicArray#(.t: t)

        assume allocator := _init_allocator

        element_size :: UIntNative = size_of(.type = t)
        actual_capacity ::= _init_capacity

        if actual_capacity == 0 {
            actual_capacity = 1
        }

        bytes ::= actual_capacity * element_size

        if element_size != 0 and bytes / element_size != actual_capacity {
            result = ..error(.reason = ..out_of_memory)
            return
        }

        allocated ::= allocate#(.t: t)(_init_allocator, .count = actual_capacity)

        match allocated {
            ..ok ~payload {
                constructed = (
                    ._allocation = ~payload
                    ._length     = 0
                    ._capacity   = actual_capacity
                    ._shape      = (.marker = 0)
                )
                result = ..ok ~constructed
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
            }
        }
    }
)

implement#(.t: Type) Deinit#(DynamicArray#(.t: t)) (
    .deinit = (.self: $&DynamicArray#(.t: t)) -> () {
        -- Lexical owners recursively destroy fields in logical order.
        i :: UIntNative = 0

        while i < self&._length {
            slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = i)
            discarded ::= ~_trusted_uninit_take#(.t: t)(
                .allocation = $&self&._allocation, .slot = slot
            )
            i = i + 1
        }
        -- Capacity records whether backing allocation ownership exists.
        trusted_opaque_mark_empty(.storage = $&self&._allocation)

        if self&._capacity != 0 {
            deinit(.self = $&self&._allocation)
        }
    }
)

implement#(
    .Provider: Type: Allocator, .t: Type: FalliblyCopyable#(.Value: t, .Provider: Provider)
) FalliblyCopyable#(DynamicArray#(t), Provider) (
    .reasons : Type = choice_union#(
        .a: FalliblyCopyable#(t, Provider).reasons, .b: (..out_of_memory)
    )
    .copy = (.self: &DynamicArray#(t), .allocator: $&Provider) -> (
        .result : Errable#(DynamicArray#(t), reasons)
    ) {
        assume allocator
        out ::= DynamicArray#(t)(.allocator = allocator, .capacity = self&._length)!
        i :: UIntNative = 0
        while i < self&._length {
            ptr ::= _trusted_dynamic_array_element_reference#(t)(
                .array = self, .offset = i
            ).pointer
            copied ::= FalliblyCopyable#(t, Provider).copy(ptr, .allocator = allocator)!
            push_assume_capacity#(t)($&out, .value = ~copied)
            i = i + 1
        }
        result = ..ok ~out
    }
)

-- Only the occupied prefix may cross from a slot handle to a normal reference.
_trusted_dynamic_array_element_reference := #(.t: Type) (
    .array: &DynamicArray#(.t: t), .offset: UIntNative
) -> (.pointer: &t) {
    if offset >= array&._length { abort }
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &array&._allocation, .index = offset)
    slot_index: ?UIntNative = ..some(.value = slot._index)
    mutable ::= trusted_establish_allocation_slot#(.t: t)(
        .allocation = &array&._allocation
        .slot       = slot._raw
        .index      = slot_index
        .anchor     = array&._allocation.anchor
    ).reference
    pointer = read_reference#(.t: t)(.base = mutable).reference
}

_trusted_dynamic_array_element_mutable_reference := #(.t: Type) (
    .array: $&DynamicArray#(.t: t), .offset: UIntNative
) -> (.pointer: $&t) {
    if offset >= array&._length { abort }
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &array&._allocation, .index = offset)
    slot_index: ?UIntNative = ..some(.value = slot._index)
    pointer = trusted_establish_allocation_slot#(.t: t)(
        .allocation = &array&._allocation
        .slot       = slot._raw
        .index      = slot_index
        .anchor     = array&._allocation.anchor
    ).reference
}

-- Ensures space for at least `capacity` elements without changing length.
-- Callers that must commit an external resource after a successful capacity
-- check can follow this with `push_assume_capacity` without another OOM point.
ensure_capacity := #(.t: Type, .Provider: Type: Allocator) (
    .allocator: $&Provider, .self: $&DynamicArray#(.t: t), .capacity: UIntNative
) -> (.result: Errable#(Void, (..out_of_memory))) {
    assume allocator

    if self&._capacity >= capacity {
        result = ..ok Void()
        return
    }

    result = _grow_dynamic_array(
        .allocator = allocator, .array = self, .min_capacity = capacity
    )
}

_grow_dynamic_array := #(.t: Type, .Provider: Type: Allocator) (
    .allocator: $&Provider, .array: $&DynamicArray#(.t: t), .min_capacity: UIntNative
) -> (.result: Errable#(Void, (..out_of_memory))) {
    assume allocator

    element_size :: UIntNative = size_of(.type = t)
    maximum ::= integer_limits(.value = min_capacity).maximum

    if element_size != 0 { maximum = maximum / element_size }
    if min_capacity > maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    -- Reserve geometrically so repeated appends relocate a linear number of
    -- elements. Clamp before multiplying, including the allocation byte size.
    new_capacity ::= array&._capacity

    if new_capacity == 0 {
        new_capacity = 1
    } else {
        if new_capacity <= maximum / 2 {
            new_capacity = new_capacity * 2
        } else {
            new_capacity = maximum
        }
    }

    if new_capacity < min_capacity { new_capacity = min_capacity }
    if new_capacity > maximum { new_capacity = maximum }
    allocate_result ::= Allocator#(
        Provider
    ).allocate(
        .self      = allocator
        .size      = element_size * new_capacity
        .alignment = alignment_of(.type = t)
    )

    match allocate_result {
        ..ok ~payload {
            new_allocation ::= ~payload
            i :: UIntNative = 0
            while i < array&._length {
                old_slot ::= _trusted_uninit_slot#(.t: t)(
                    .allocation = &array&._allocation, .index = i
                )
                new_slot ::= _trusted_uninit_slot#(.t: t)(
                    .allocation = &new_allocation, .index = i
                )
                _trusted_uninit_relocate#(.t: t)(
                    .source_allocation      = &array&._allocation
                    .source                 = old_slot
                    .destination_allocation = &new_allocation
                    .destination            = new_slot
                )
                i = i + 1
            }

            deinit(.self = $&array&._allocation)

            _invalidate_dynamic_array_shape#(.t: t)(.array = array)
            array&= (
                ._allocation = ~new_allocation
                ._length     = array&._length
                ._capacity   = new_capacity
                ._shape      = (.marker = 0)
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

-- Appends without allocation. The caller must first ensure `length < capacity`,
-- normally through `ensure_capacity`.
push_assume_capacity := #(.t: Type) (.self: $&DynamicArray#(.t: t), .value: t) -> () {
    if self&._length >= self&._capacity { abort }
    offset ::= self&._length
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = offset)
    _trusted_uninit_write#(.t: t)(
        .allocation = $&self&._allocation, .slot = slot, .value = ~value
    )
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)
    self&._length = offset + 1
}

insert_growing := #(.t: Type, .AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator: $&AllocatorType, .self: $&DynamicArray#(.t: t), .index: UIntNative, .value: t
) -> (.result: Errable#(Void, (..out_of_memory, ..out_of_bounds))) {
    assume allocator
    owned ::= ~value

    if index > self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if self&._length == integer_limits(.value = self&._length).maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    one :: UIntNative = 1
    current_length ::= self&._length

    if self&._length == self&._capacity {
        growth_result ::= _grow_dynamic_array(
            .allocator = allocator, .array = self, .min_capacity = [self&._length + one]
        )
        match growth_result {
            ..ok _ {
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
        current_length = self&._length
    }

    cursor ::= current_length

    while cursor > index {
        source_index ::= cursor - one
        source_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation, .index = source_index
        )
        destination_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation, .index = cursor
        )
        _trusted_uninit_relocate#(.t: t)(
            .source_allocation      = &self&._allocation
            .source                 = source_slot
            .destination_allocation = &self&._allocation
            .destination            = destination_slot
        )
        cursor = source_index
    }

    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = index)
    _trusted_uninit_write#(.t: t)(
        .allocation = $&self&._allocation, .slot = slot, .value = ~owned
    )
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)
    self&._length = current_length + one

    result = ..ok Void()
}

-- A lexical owner recursively destroys fields, including structural values
-- with no nominal destructor of their own.
_destroy_array_element := #(.t: Type, .AllocatorType: Type: Allocator#(AllocatorType)) (
    .value: t, .allocator: $&AllocatorType
) -> () {
    assume allocator
    discarded ::= ~value
}

replace := #(.t: Type, .AllocatorType: Type: Allocator#(AllocatorType)) (
    .self: $&DynamicArray#(.t: t), .index: UIntNative, .value: t, .allocator: $&AllocatorType
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    assume allocator
    owned ::= ~value

    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = index)
    -- Extract before destroying so nested owners receive ordinary lexical
    -- cleanup. Finish that cleanup before installing the replacement.
    _destroy_array_element#(.t: t)(
        .value = ~_trusted_uninit_take#(.t: t)(
            .allocation = $&self&._allocation, .slot = slot
        )
        .allocator = allocator
    )
    _trusted_uninit_write#(.t: t)(
        .allocation = $&self&._allocation, .slot = slot, .value = ~owned
    )
    -- Replacement ends the old content lifetime even when its address stays.
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)

    result = ..ok Void()
}

-- Internal collection operations may rely on their own index invariants.
-- These entrypoints still check length at runtime, but do not add Errable to
-- every internal lookup in an already validated data structure.
_trusted_dynamic_array_get := #(.t: Type: ImplicitlyCopyable) (
    .array: &DynamicArray#(.t: t), .index: UIntNative
) -> (.value: t) {
    value = _trusted_dynamic_array_element_reference#(.t: t)(
        .array = array, .offset = index
    ).pointer&
}

_trusted_dynamic_array_get_reference := #(.t: Type) (
    .array: &DynamicArray#(.t: t), .index: UIntNative
) -> (.reference: &t) {
    reference = _trusted_dynamic_array_element_reference#(.t: t)(
        .array = array, .offset = index
    ).pointer
}

_trusted_dynamic_array_get_mutable_reference := #(.t: Type) (
    .array: $&DynamicArray#(.t: t), .index: UIntNative
) -> (.reference: $&t) {
    reference = _trusted_dynamic_array_element_mutable_reference#(.t: t)(
        .array = array, .offset = index
    ).pointer
}

-- This helper replaces copyable slot metadata. Owning values must use set,
-- which extracts the old value into a lexical owner for recursive cleanup.
_trusted_dynamic_array_set := #(.t: Type: ImplicitlyCopyable) (
    .array: $&DynamicArray#(.t: t), .index: UIntNative, .value: t
) -> () {
    ptr ::= _trusted_dynamic_array_element_mutable_reference#(.t: t)(
        .array = array, .offset = index
    ).pointer
    trusted_opaque_drop(.slot = ptr)
    trusted_opaque_move_in#(.t: t, .storage_type: Allocation)(
        .storage = $&array&._allocation, .destination = ptr, .source = ~value
    )
    _invalidate_dynamic_array_shape#(.t: t)(.array = array)
}

implement#(.t: Type) Indexable#(DynamicArray#(.t: t)) (
    .Item : Type = t

    .length = (.self: &DynamicArray#(.t: t)) -> (.count: UIntNative) {
        count = self&._length
    }

    .get_reference = (.self: &DynamicArray#(.t: t), .index: UIntNative) -> (
        .result : Errable#(&t, (..out_of_bounds))
    ) {
        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = ..ok dynamic_array_element_reference#(.t: t)(
            .array = self, .offset = index
        ).pointer
    }
)

implement#(.t: Type, .Provider: Type: Allocator#(Provider)) Resizable#(
    DynamicArray#(.t: t), Provider
) (
    .Item : Type = t

    .push = (.self: $&DynamicArray#(.t: t), .value: t, .allocator: $&Provider) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) {
        assume allocator
        owned ::= ~value

        if self&._length == integer_limits(.value = self&._length).maximum {
            result = ..error(.reason = ..out_of_memory)
            return
        }

        one :: UIntNative = 1

        if self&._length == self&._capacity {
            growth_result ::= _grow_dynamic_array(
                .allocator = allocator, .array = self, .min_capacity = [self&._length + one]
            )
            match growth_result {
                ..ok _ {
                }
                ..error _ {
                    result = ..error(.reason = ..out_of_memory)
                    return
                }
            }
        }

        push_assume_capacity#(.t: t)(self, .value = ~owned)

        result = ..ok Void()
    }

    .insert = (
        .self: $&DynamicArray#(.t: t), .index: UIntNative, .value: t, .allocator: $&Provider
    ) -> (.result: Errable#(Void, (..out_of_memory, ..out_of_bounds))) {
        assume allocator
        owned ::= ~value

        if index > self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = insert_growing#(.t: t)(
            .allocator = allocator, .self = self, .index = index, .value = ~owned
        )
    }
)

implement#(.t: Type) Removable#(DynamicArray#(.t: t)) (
    .Item : Type = t

    .pop = (.self: $&DynamicArray#(.t: t)) -> (.result: Errable#(t, (..empty))) {
        if self&._length == 0 {
            result = ..error(.reason = ..empty)
            return
        }

        one :: UIntNative = 1
        new_length ::= self&._length - one
        slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation, .index = new_length
        )
        moved_out ::= _trusted_uninit_take#(.t: t)(
            .allocation = $&self&._allocation, .slot = slot
        )
        _invalidate_dynamic_array_shape#(.t: t)(.array = self)
        self&._length = new_length

        result = ..ok ~moved_out
    }

    .remove = (.self: $&DynamicArray#(.t: t), .index: UIntNative) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) {
        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        one :: UIntNative = 1
        new_length ::= self&._length - one
        removed_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation, .index = index
        )
        moved_out ::= _trusted_uninit_take#(.t: t)(
            .allocation = $&self&._allocation, .slot = removed_slot
        )

        cursor ::= index

        while cursor < new_length {
            source_slot ::= _trusted_uninit_slot#(.t: t)(
                .allocation = &self&._allocation, .index = [cursor + one]
            )
            destination_slot ::= _trusted_uninit_slot#(.t: t)(
                .allocation = &self&._allocation, .index = cursor
            )
            _trusted_uninit_relocate#(.t: t)(
                .source_allocation      = &self&._allocation
                .source                 = source_slot
                .destination_allocation = &self&._allocation
                .destination            = destination_slot
            )
            cursor = cursor + one
        }

        _invalidate_dynamic_array_shape#(.t: t)(.array = self)
        self&._length = new_length

        result = ..ok ~moved_out
    }
)

implement#(.t: Type: ImplicitlyCopyable) IndexableValue#(DynamicArray#(.t: t)) (
    .Item : Type = t

    .get = (.self: &DynamicArray#(.t: t), .index: UIntNative) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) {
        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        ptr ::= _trusted_dynamic_array_element_reference#(.t: t)(
            .array = self, .offset = index
        ).pointer

        result = ..ok ptr&
    }
)

implement#(.t: Type) MutableIndexable#(DynamicArray#(.t: t)) (
    .Item : Type = t

    .get_mutable_reference = (.self: $&DynamicArray#(.t: t), .index: UIntNative) -> (
        .result : Errable#($&t, (..out_of_bounds))
    ) {
        if index >= self&._length {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = ..ok dynamic_array_element_mutable_reference#(.t: t)(
            .array = self, .offset = index
        ).pointer
    }
)
