-- A shape generation gives borrowed views an invalidation
-- boundary independent of allocation roots. Structural changes renew it;
-- replacing an element's value without changing shape does not.
_DynamicArrayShape: Type = (.marker: UInt8)

_DynamicArrayShape deinit(.self: $&_DynamicArrayShape) -> () := {}

DynamicArray#(.t: Type): Type = (
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

length#(.t: Type)(.self: &DynamicArray#(.t: t)) -> (.count: UIntNative) := {
    count = self&._length
}

capacity#(.t: Type)(.self: &DynamicArray#(.t: t)) -> (.count: UIntNative) := {
    count = self&._capacity
}

-- An owner that has consumed every element may need to expose the empty
-- opaque storage state to the safety checker before ending a temporal root.
_trusted_dynamic_array_mark_empty#(.t: Type)(.self: $&DynamicArray#(.t: t)) -> () := {
    if self&._length != 0 { abort }
    trusted_opaque_mark_empty(.storage = $&self&._allocation)
}

DynamicArray init#(
        .t : Type
    )(
        .allocator : $&Allocator,
        .capacity  : UIntNative,
    ) -> (
        .result : Errable#(DynamicArray#(.t: t), (..out_of_memory))
    ) := {
    constructed :: DynamicArray#(.t: t)

    assume allocator

    element_size :: UIntNative = size_of(.type = t)
    actual_capacity ::= capacity

    if actual_capacity == 0 {
        actual_capacity = 1
    }

    bytes ::= actual_capacity * element_size

    if element_size != 0 and bytes / element_size != actual_capacity {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    allocated ::= allocate#(.t: t)(.self = allocator, .count = actual_capacity)

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

DynamicArray deinit#(
        .t : Type
    )(
        .allocator : $&Allocator,
        .self      : $&DynamicArray#(.t: t)
    ) -> () := {
    assume allocator

    -- Lexical owners recursively destroy fields in logical order.
    i :: UIntNative = 0

    while i < self&._length {
        slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = i)
        discarded ::= ~_trusted_uninit_take#(.t: t)(
            .allocation = $&self&._allocation
            .slot       = slot
        )
        i = i + 1
    }
    -- Capacity records whether backing allocation ownership exists.
    trusted_opaque_mark_empty(.storage = $&self&._allocation)

    if self&._capacity != 0 {
        deinit(.self = $&self&._allocation)
    }
}

copy#(
        .t : Type: InfalliblyCopyable
    )(
        .self      : &DynamicArray#(.t: t),
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(DynamicArray#(.t: t), (..out_of_memory))
    ) := {
    assume allocator

    -- Copying an owning element still requires an explicit element copy
    -- operation; a plain slot read is insufficient for owning `t`.
    out :: DynamicArray#(.t: t)
    initialized ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = self&._length)

    match initialized {
        ..ok ~constructed_value { out = ~constructed_value }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    i :: UIntNative = 0

    while i < self&._length {
        ptr ::= _trusted_dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = i).pointer
        element ::= copy(.self = ptr)
        pushed ::= push#(.t: t)(.allocator = allocator, .self = $&out, .value = ~element)
        if is(.value = pushed, .variant = ..error) {
            deinit#(.t: t)(.allocator = allocator, .self = $&out)
            result = ..error(.reason = ..out_of_memory)
            return
        }
        i = i + 1
    }

    result = ..ok ~out
}

DynamicArray#(.t: Type: InfalliblyCopyable) implements FalliblyCopyable#(
    .reasons : (..out_of_memory)
)

copy#(
        .t               : Type: FalliblyCopyable#(.reasons: element_reasons),
        .element_reasons : Type,
    )(
        .self      : &DynamicArray#(.t: t),
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(
            DynamicArray#(.t: t),
            choice_union#(.a: element_reasons, .b: (..out_of_memory))
        )
    ) := {
    assume allocator

    out :: DynamicArray#(.t: t)
    initialized ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = self&._length)

    match initialized {
        ..ok ~constructed_value { out = ~constructed_value }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    i :: UIntNative = 0

    while i < self&._length {
        ptr ::= _trusted_dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = i).pointer
        copied ::= copy(.self = ptr)
        match copied {
            ..ok ~payload {
                push_assume_capacity#(.t: t)(.self = $&out, .value = ~payload)
            }
            ..error ~err {
                deinit#(.t: t)(.allocator = allocator, .self = $&out)
                result = ..error(.reason = err.reason)
                return
            }
        }
        i = i + 1
    }

    result = ..ok ~out
}

DynamicArray#(.t: Type: FalliblyCopyable#(.reasons: element_reasons)) implements FalliblyCopyable#(
    .reasons : choice_union#(.a: element_reasons, .b: (..out_of_memory)),
)

-- Only the occupied prefix may cross from a slot handle to a normal reference.
_trusted_dynamic_array_element_ro_pointer#(
        .t : Type
    )(
        .array  : &DynamicArray#(.t: t),
        .offset : UIntNative,
    ) -> (
        .pointer : &t
    ) := {
    if offset >= array&._length { abort }
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &array&._allocation, .index = offset)
    mutable ::= trusted_establish_allocation_slot#(.t: t)(
        .allocation = &array&._allocation
        .slot       = slot._raw
        .anchor     = array&._allocation.anchor
    ).reference
    pointer = read_reference#(.t: t)(.base = mutable).reference
}

_trusted_dynamic_array_element_rw_pointer#(
        .t : Type
    )(
        .array  : $&DynamicArray#(.t: t),
        .offset : UIntNative,
    ) -> (
        .pointer : $&t
    ) := {
    if offset >= array&._length { abort }
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &array&._allocation, .index = offset)
    pointer = trusted_establish_allocation_slot#(.t: t)(
        .allocation = &array&._allocation
        .slot       = slot._raw
        .anchor     = array&._allocation.anchor
    ).reference
}

dynamic_array_grow#(
        .t : Type
    )(
        .allocator    : $&Allocator,
        .array        : $&DynamicArray#(.t: t),
        .min_capacity : UIntNative,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    result = dynamic_array_grow_growing#(.t: t)(
        .allocator    = allocator
        .array        = array
        .min_capacity = min_capacity
    )
}

-- Ensures space for at least `capacity` elements without changing length.
-- Callers that must commit an external resource after a successful capacity
-- check can follow this with `push_assume_capacity` without another OOM point.
ensure_capacity#(
        .t : Type
    )(
        .allocator : $&Allocator,
        .self      : $&DynamicArray#(.t: t),
        .capacity  : UIntNative,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    if self&._capacity >= capacity {
        result = ..ok Void()
        return
    }

    result = dynamic_array_grow_growing#(.t: t)(
        .allocator    = allocator
        .array        = self
        .min_capacity = capacity
    )
}

dynamic_array_grow_growing#(
        .t : Type
    )(
        .allocator    : $&Allocator,
        .array        : $&DynamicArray#(.t: t),
        .min_capacity : UIntNative,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
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

    if new_capacity == 0 { new_capacity = 1 } else {
        if new_capacity <= maximum / 2 { new_capacity = new_capacity * 2 } else {
            new_capacity = maximum
        }
    }

    if new_capacity < min_capacity { new_capacity = min_capacity }
    if new_capacity > maximum { new_capacity = maximum }
    allocate_result ::= allocate#(.t: t)(.self = allocator, .count = new_capacity)

    match allocate_result {
        ..ok ~payload {
            new_allocation ::= ~payload
            i :: UIntNative = 0
            while i < array&._length {
                old_slot ::= _trusted_uninit_slot#(.t: t)(
                    .allocation = &array&._allocation
                    .index      = i
                )
                new_slot ::= _trusted_uninit_slot#(.t: t)(
                    .allocation = &new_allocation
                    .index      = i
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

push#(
        .t : Type
    )(
        .allocator : $&Allocator,
        .self      : $&DynamicArray#(.t: t),
        .value     : t,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator
    owned ::= ~value

    if self&._length == integer_limits(.value = self&._length).maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    one :: UIntNative = 1

    if self&._length == self&._capacity {
        growth_result ::= dynamic_array_grow_growing#(.t: t)(
            .allocator    = allocator
            .array        = self
            .min_capacity = [
                self&._length
                + one
            ]
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

    push_assume_capacity#(.t: t)(.self = self, .value = ~owned)

    result = ..ok Void()
}

-- Appends without allocation. The caller must first ensure `length < capacity`,
-- normally through `ensure_capacity`.
push_assume_capacity#(
        .t : Type
    )(
        .self  : $&DynamicArray#(.t: t),
        .value : t,
    ) -> () := {
    if self&._length >= self&._capacity { abort }
    offset ::= self&._length
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = offset)
    _trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = slot, .value = ~value)
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)
    self&._length = offset + 1
}

pop#(
        .t : Type
    )(
        .self : $&DynamicArray#(.t: t),
    ) -> (
        .result : Errable#(t, (..empty))
    ) := {
    if self&._length == 0 {
        result = ..error(.reason = ..empty)
        return
    }

    one :: UIntNative = 1
    new_length ::= self&._length - one
    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = new_length)
    moved_out ::= _trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = slot)
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)
    self&._length = new_length

    result = ..ok ~moved_out
}

insert#(
        .t : Type
    )(
        .allocator : $&Allocator,
        .self      : $&DynamicArray#(.t: t),
        .i         : UIntNative,
        .value     : t,
    ) -> (
        .result : Errable#(Void, (..out_of_memory, ..out_of_bounds))
    ) := {
    assume allocator
    owned ::= ~value

    if i > self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = insert_growing#(.t: t)(.allocator = allocator, .self = self, .i = i, .value = ~owned)
}

insert_growing#(
        .t : Type
    )(
        .allocator : $&Allocator,
        .self      : $&DynamicArray#(.t: t),
        .i         : UIntNative,
        .value     : t,
    ) -> (
        .result : Errable#(Void, (..out_of_memory, ..out_of_bounds))
    ) := {
    assume allocator
    owned ::= ~value

    if i > self&._length {
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
        growth_result ::= dynamic_array_grow_growing#(.t: t)(
            .allocator    = allocator
            .array        = self
            .min_capacity = [
                self&._length
                + one
            ]
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

    while cursor > i {
        source_index ::= cursor - one
        source_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation
            .index      = source_index
        )
        destination_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation
            .index      = cursor
        )
        _trusted_uninit_relocate#(.t: t)(
            .source_allocation      = &self&._allocation
            .source                 = source_slot
            .destination_allocation = &self&._allocation
            .destination            = destination_slot
        )
        cursor = source_index
    }

    slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = i)
    _trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = slot, .value = ~owned)
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)
    self&._length = current_length + one

    result = ..ok Void()
}

remove#(
        .t : Type
    )(
        .self : $&DynamicArray#(.t: t),
        .i    : UIntNative,
    ) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) := {
    if i >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    one :: UIntNative = 1
    new_length ::= self&._length - one
    removed_slot ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = i)
    moved_out ::= _trusted_uninit_take#(.t: t)(
        .allocation = $&self&._allocation
        .slot       = removed_slot
    )

    cursor ::= i

    while cursor < new_length {
        source_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation
            .index      = [
                cursor
                + one
            ]
        )
        destination_slot ::= _trusted_uninit_slot#(.t: t)(
            .allocation = &self&._allocation
            .index      = cursor
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

get#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : &DynamicArray#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    ptr ::= _trusted_dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = index).pointer

    result = ..ok ptr&
}

get_ro_ref#(
        .t : Type
    )(
        .self  : &DynamicArray#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#(&t, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = ..ok dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = index).pointer
}

get_rw_ref#(
        .t : Type
    )(
        .self  : $&DynamicArray#(.t: t),
        .index : UIntNative,
    ) -> (
        .result : Errable#($&t, (..out_of_bounds))
    ) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = ..ok dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = index).pointer
}

-- A lexical owner recursively destroys fields, including structural values
-- with no nominal destructor of their own.
_destroy_array_element#(.t: Type)(.value: t, .allocator: $&Allocator) -> () := {
    assume allocator
    discarded ::= ~value
}

set#(
        .t : Type
    )(
        .self      : $&DynamicArray#(.t: t),
        .index     : UIntNative,
        .value     : t,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_bounds))
    ) := {
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
        .value     = ~_trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = slot)
        .allocator = allocator
    )
    _trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = slot, .value = ~owned)
    -- Replacement ends the old content lifetime even when its address stays.
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)

    result = ..ok Void()
}

-- Internal collection operations may rely on their own index invariants.
-- These entrypoints still check length at runtime, but do not add Errable to
-- every internal lookup in an already validated data structure.
_trusted_dynamic_array_get#(
        .t : Type: ImplicitlyCopyable
    )(
        .array : &DynamicArray#(.t: t),
        .index : UIntNative,
    ) -> (
        .value : t
    ) := {
    value = _trusted_dynamic_array_element_ro_pointer#(.t: t)(.array = array, .offset = index).pointer&
}

_trusted_dynamic_array_get_ro_ref#(
        .t : Type
    )(
        .array : &DynamicArray#(.t: t),
        .index : UIntNative,
    ) -> (
        .reference : &t
    ) := {
    reference = _trusted_dynamic_array_element_ro_pointer#(.t: t)(.array = array, .offset = index).pointer
}

_trusted_dynamic_array_get_rw_ref#(
        .t : Type
    )(
        .array : $&DynamicArray#(.t: t),
        .index : UIntNative,
    ) -> (
        .reference : $&t
    ) := {
    reference = _trusted_dynamic_array_element_rw_pointer#(.t: t)(.array = array, .offset = index).pointer
}

-- This helper replaces copyable slot metadata. Owning values must use set,
-- which extracts the old value into a lexical owner for recursive cleanup.
_trusted_dynamic_array_set#(
        .t : Type: ImplicitlyCopyable
    )(
        .array : $&DynamicArray#(.t: t),
        .index : UIntNative,
        .value : t,
    ) -> () := {
    ptr ::= _trusted_dynamic_array_element_rw_pointer#(.t: t)(.array = array, .offset = index).pointer
    trusted_opaque_drop(.slot = ptr)
    trusted_opaque_move_in#(.t: t, .storage_type: Allocation)(
        .storage     = $&array&._allocation
        .destination = ptr
        .source      = ~value
    )
    _invalidate_dynamic_array_shape#(.t: t)(.array = array)
}

DynamicArray#(.t: Type) implements Indexable#(.t: t)
DynamicArray#(.t: Type) implements IndexableMutable#(.t: t)
DynamicArray#(.t: Type: ImplicitlyCopyable) implements IndexableValue#(.t: t)
DynamicArray#(.t: Type) implements Resizable#(.t: t)
