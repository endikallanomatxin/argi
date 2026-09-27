DynamicArray #(.t: Type) : Type = (
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
    ._length     : UIntNative
    ._capacity   : UIntNative
    --
    -- Views into the array should use `ListViewRO#(.list_type=Self, .list_value_type=t)`
    -- or `ListViewRW#(.list_type=Self, .list_value_type=t)` and remain non-owning.
)

length #(.t: Type)(.self: &DynamicArray#(.t: t)) -> (.count: UIntNative) := {
    count = self&._length
}

capacity #(.t: Type)(.self: &DynamicArray#(.t: t)) -> (.count: UIntNative) := {
    count = self&._capacity
}

-- An owner that has consumed every element may need to expose the empty
-- opaque storage state to the safety checker before ending a temporal root.
trusted_dynamic_array_mark_empty #(.t: Type)(.self: $&DynamicArray#(.t: t)) -> () := {
    if self&._length != 0 { abort }
    trusted_opaque_mark_empty(.storage = $&self&._allocation)
}

init #(.t: Type) (
    .p: $&DynamicArray#(.t: t),
    .allocator: $&Allocator,
    .capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
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
    allocated ::= allocate(.self = allocator, .size = bytes)
    match allocated {
        ..ok ~ payload {
            p& = (
                ._allocation = ~payload,
                ._length = 0,
                ._capacity = actual_capacity,
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

deinit #(.t: Type) (
    .allocator: $&Allocator,
    .self: $&DynamicArray#(.t: t)
) -> () := {
    assume allocator

    i :: UIntNative = 0
    while i < self&._length {
        slot ::= trusted_dynamic_array_storage_pointer#(.t: t)(.array = self, .offset = i).pointer
        trusted_opaque_drop(.slot = slot, .allocator = allocator)
        i = i + 1
    }
    -- Error traces use the all-zero representation as an empty array until
    -- their first entry is appended. Regular initialization always gives an
    -- array nonzero capacity, so capacity also records whether backing
    -- allocation ownership exists.
    trusted_opaque_mark_empty(.storage = $&self&._allocation)
    if self&._capacity != 0 {
        deinit(.self = $&self&._allocation)
    }
}

copy #(.t: Type: InfalliblyCopyable) (
    .self: &DynamicArray#(.t: t),
    .allocator: $&Allocator,
) -> (.result: Errable#(.t: DynamicArray#(.t: t), .reasons: (..out_of_memory))) := {
    assume allocator

    -- Copying an owning element still requires an explicit element copy
    -- operation; a plain slot read is insufficient for owning `t`.
    out :: DynamicArray#(.t: t)
    initialized ::= init#(.t: t)(.p = $&out, .allocator = allocator, .capacity = self&._length)
    if is(.value = initialized, .variant = ..error) {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    i :: UIntNative = 0
    while i < self&._length {
        ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = i).pointer
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

DynamicArray#(.t: Type: InfalliblyCopyable) implements FalliblyCopyable#(.reasons: (..out_of_memory))

copy #(
    .t: Type: FalliblyCopyable#(.reasons: element_reasons),
    .element_reasons: Type,
) (
    .self: &DynamicArray#(.t: t),
    .allocator: $&Allocator,
) -> (.result: Errable#(
    .t: DynamicArray#(.t: t),
    .reasons: choice_union#(.a: element_reasons, .b: (..out_of_memory)),
)) := {
    assume allocator

    out :: DynamicArray#(.t: t)
    initialized ::= init#(.t: t)(.p = $&out, .allocator = allocator, .capacity = self&._length)
    if is(.value = initialized, .variant = ..error) {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    i :: UIntNative = 0
    while i < self&._length {
        ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = i).pointer
        copied ::= copy(.self = ptr)
        match copied {
            ..ok ~ payload {
                push_assume_capacity#(.t: t)(.self = $&out, .value = ~payload)
            }
            ..error ~ err {
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
    .reasons: choice_union#(.a: element_reasons, .b: (..out_of_memory)),
)

dynamic_array_element_ro_pointer #(.t: Type) (
    .array: &DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.pointer: &t) := {
    if offset >= array&._length { abort }
    base ::= reinterpret_reference#(.from: UInt8, .to: t)(.base = array&._allocation.data).reference
    pointer = reference_offset#(.t: t)(.base = base, .elements = offset).reference
}

-- Only the occupied prefix may be exposed as a normal mutable reference.
dynamic_array_element_rw_pointer #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.pointer: $&t) := {
    if offset >= array&._length { abort }
    pointer = trusted_dynamic_array_storage_pointer#(.t: t)(.array = array, .offset = offset).pointer
}

-- Opaque operations may address empty slots, but must maintain length and
-- exactly-once occupancy themselves.
trusted_dynamic_array_storage_pointer #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.pointer: $&t) := {
    -- Internal callers also use the empty slot at length during insertion.
    if offset >= array&._capacity { abort }
    base ::= mutable_reinterpret_reference#(.from: UInt8, .to: t)(.base = array&._allocation.data).reference
    pointer = mutable_reference_offset#(.t: t)(.base = base, .elements = offset).reference
}

dynamic_array_grow #(.t: Type) (
    .allocator: $&Allocator,
    .array: $&DynamicArray#(.t: t),
    .min_capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume allocator

    result = dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = array, .min_capacity = min_capacity)
}

-- Ensures space for at least `capacity` elements without changing length.
-- Callers that must commit an external resource after a successful capacity
-- check can follow this with `push_assume_capacity` without another OOM point.
ensure_capacity #(.t: Type) (
    .allocator: $&Allocator,
    .self: $&DynamicArray#(.t: t),
    .capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume allocator

    if self&._capacity >= capacity {
        result = ..ok Void()
        return
    }
    result = dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = self, .min_capacity = capacity)
}

dynamic_array_grow_growing #(.t: Type) (
    .allocator: $&Allocator,
    .array: $&DynamicArray#(.t: t),
    .min_capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume allocator

    element_size :: UIntNative = size_of(.type = t)
    new_capacity ::= array&._capacity
    zero :: UIntNative = 0
    one :: UIntNative = 1

    if new_capacity == zero {
        new_capacity = one
    }

    if new_capacity < min_capacity {
        new_capacity = min_capacity
    }

    new_bytes :: UIntNative = new_capacity * element_size
    if element_size != 0 and new_bytes / element_size != new_capacity {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    allocate_result ::= allocate(.self = allocator, .size = new_bytes)
    match allocate_result {
        ..ok ~ payload {
            new_allocation ::= ~payload
            old_base ::= mutable_reinterpret_reference#(.from: UInt8, .to: t)(.base = array&._allocation.data).reference
            new_base ::= mutable_reinterpret_reference#(.from: UInt8, .to: t)(.base = new_allocation.data).reference
            i :: UIntNative = 0
            while i < array&._length {
                old_slot ::= mutable_reference_offset#(.t: t)(.base = old_base, .elements = i).reference
                new_slot ::= mutable_reference_offset#(.t: t)(.base = new_base, .elements = i).reference
                trusted_opaque_relocate(.source = old_slot, .destination = new_slot)
                i = i + 1
            }

            deinit(.self = $&array&._allocation)

            array& = (
                ._allocation = ~new_allocation,
                ._length = array&._length,
                ._capacity = new_capacity,
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

push #(.t: Type) (
    .allocator: $&Allocator,
    .self: $&DynamicArray#(.t: t),
    .value: t,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume allocator

    one :: UIntNative = 1

    if self&._length == self&._capacity {
        growth_result ::= dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = self, .min_capacity = self&._length + one)
        match growth_result {
            ..ok _ {
            }
            ..error _ {
                trusted_opaque_drop(.slot = $&value, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    push_assume_capacity#(.t: t)(.self = self, .value = ~value)
    result = ..ok Void()
}

-- Appends without allocation. The caller must first ensure `length < capacity`,
-- normally through `ensure_capacity`.
push_assume_capacity #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .value: t,
) -> () := {
    if self&._length >= self&._capacity { abort }
    offset ::= self&._length
    slot ::= trusted_uninit_slot#(.t: t)(.allocation = $&self&._allocation, .index = offset)
    trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = slot, .value = ~value)
    self&._length = offset + 1
}

pop #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
) -> (.result: Errable#(.t: t, .reasons: (..empty))) := {
    if self&._length == 0 {
        result = ..error(.reason = ..empty)
        return
    }
    one :: UIntNative = 1
    new_length ::= self&._length - one
    slot ::= trusted_uninit_slot#(.t: t)(.allocation = $&self&._allocation, .index = new_length)
    moved_out ::= trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = slot)
    self&._length = new_length
    result = ..ok ~moved_out
}

insert #(.t: Type) (
    .allocator: $&Allocator,
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory, ..out_of_bounds))) := {
    assume allocator

    if i > self&._length {
        trusted_opaque_drop(.slot = $&value, .allocator = allocator)
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = insert_growing#(.t: t)(.allocator = allocator, .self = self, .i = i, .value = ~value)
}

insert_growing #(.t: Type) (
    .allocator: $&Allocator,
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory, ..out_of_bounds))) := {
    assume allocator

    if i > self&._length {
        trusted_opaque_drop(.slot = $&value, .allocator = allocator)
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    one :: UIntNative = 1
    current_length ::= self&._length

    if self&._length == self&._capacity {
        growth_result ::= dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = self, .min_capacity = self&._length + one)
        match growth_result {
            ..ok _ {
            }
            ..error _ {
                trusted_opaque_drop(.slot = $&value, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
        current_length = self&._length
    }

    cursor ::= current_length
    while cursor > i {
        source_index ::= cursor - one
        source_slot ::= trusted_dynamic_array_storage_pointer#(.t: t)(.array = self, .offset = source_index).pointer
        destination_slot ::= trusted_dynamic_array_storage_pointer#(.t: t)(.array = self, .offset = cursor).pointer
        trusted_opaque_relocate(.source = source_slot, .destination = destination_slot)
        cursor = source_index
    }

    slot ::= trusted_uninit_slot#(.t: t)(.allocation = $&self&._allocation, .index = i)
    trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = slot, .value = ~value)
    self&._length = current_length + one
    result = ..ok Void()
}

remove #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
) -> (.result: Errable#(.t: t, .reasons: (..out_of_bounds))) := {
    if i >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    one :: UIntNative = 1
    new_length ::= self&._length - one
    removed_slot ::= trusted_uninit_slot#(.t: t)(.allocation = $&self&._allocation, .index = i)
    moved_out ::= trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = removed_slot)

    cursor ::= i
    while cursor < new_length {
        source_slot ::= trusted_dynamic_array_storage_pointer#(.t: t)(.array = self, .offset = cursor + one).pointer
        destination_slot ::= trusted_dynamic_array_storage_pointer#(.t: t)(.array = self, .offset = cursor).pointer
        trusted_opaque_relocate(.source = source_slot, .destination = destination_slot)
        cursor = cursor + one
    }

    self&._length = new_length
    result = ..ok ~moved_out
}

get #(.t: Type: ImplicitlyCopyable) (
    .self: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.result: Errable#(.t: t, .reasons: (..out_of_bounds))) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = index).pointer
    result = ..ok ptr&
}

get_ro_ref #(.t: Type) (
    .self: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.result: Errable#(.t: &t, .reasons: (..out_of_bounds))) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = index).pointer
}

get_rw_ref #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.result: Errable#(.t: $&t, .reasons: (..out_of_bounds))) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = index).pointer
}

set #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .index: UIntNative,
    .value: t,
    .allocator: $&Allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_bounds))) := {
    assume allocator
    if index >= self&._length {
        trusted_opaque_drop(.slot = $&value, .allocator = allocator)
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    ptr ::= dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = index).pointer
    trusted_opaque_drop(.slot = ptr, .allocator = allocator)
    trusted_opaque_move_in#(.t: t, .storage_type: Allocation)(
        .storage = $&self&._allocation,
        .destination = ptr,
        .source = ~value,
    )
    result = ..ok Void()
}

-- Internal collection operations may rely on their own index invariants.
-- These entrypoints still check length at runtime, but do not add Errable to
-- every internal lookup in an already validated data structure.
trusted_dynamic_array_get #(.t: Type: ImplicitlyCopyable) (
    .array: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.value: t) := {
    value = dynamic_array_element_ro_pointer#(.t: t)(.array = array, .offset = index).pointer&
}

trusted_dynamic_array_get_ro_ref #(.t: Type) (
    .array: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.reference: &t) := {
    reference = dynamic_array_element_ro_pointer#(.t: t)(.array = array, .offset = index).pointer
}

trusted_dynamic_array_get_rw_ref #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.reference: $&t) := {
    reference = dynamic_array_element_rw_pointer#(.t: t)(.array = array, .offset = index).pointer
}

trusted_dynamic_array_set #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .index: UIntNative,
    .value: t,
) -> () := {
    ptr ::= dynamic_array_element_rw_pointer#(.t: t)(.array = array, .offset = index).pointer
    trusted_opaque_drop(.slot = ptr)
    trusted_opaque_move_in#(.t: t, .storage_type: Allocation)(
        .storage = $&array&._allocation,
        .destination = ptr,
        .source = ~value,
    )
}
