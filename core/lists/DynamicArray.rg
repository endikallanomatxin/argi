DynamicArray #(.t: Type) : Type = (
    --
    -- Canonical contiguous owning dynamic list.
    --
    -- It owns heap memory through `Allocation` and should serve as the default
    -- resizable list shape in `core`.
    --
    -- Growth may reallocate and copy contents. Alternative strategies can be
    -- modeled later as separate types if needed.
    --
    .allocation : Allocation
    .length     : UIntNative
    .capacity   : UIntNative
    --
    -- Views into the array should use `ListViewRO#(.list_type=Self, .list_value_type=t)`
    -- or `ListViewRW#(.list_type=Self, .list_value_type=t)` and remain non-owning.
)

DynamicArrayIterator#(.t: Type) : Type = (
    .array : &DynamicArray#(.t: t)
    .index : UIntNative
)

DynamicArrayROPointerIterator#(.t: Type) : Type = (
    .array : &DynamicArray#(.t: t)
    .index : UIntNative
)

DynamicArrayRWPointerIterator#(.t: Type) : Type = (
    .array : $&DynamicArray#(.t: t)
    .index : UIntNative
)

DynamicArrayIterator#(.t: Type) implements Iterator#(.t: t)
DynamicArrayROPointerIterator#(.t: Type) implements Iterator#(.t: &t)
DynamicArrayRWPointerIterator#(.t: Type) implements Iterator#(.t: $&t)
DynamicArray#(.t: Type) implements Iterable#(.t: t)
DynamicArray#(.t: Type) implements ROPointerIterable#(.t: t)
DynamicArray#(.t: Type) implements RWPointerIterable#(.t: t)

init #(.t: Type) (
    .p: $&DynamicArray#(.t: t),
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    element_size :: UIntNative = size_of(.type = t)
    actual_capacity ::= capacity
    zero :: UIntNative = 0
    one :: UIntNative = 1

    if actual_capacity == zero {
        actual_capacity = one
    }

    bytes :: UIntNative = actual_capacity * element_size
    allocated ::= allocate(.self = allocator, .size = bytes)
    match allocated {
        ..ok ~ payload {
            p& = (
                .allocation = ~payload,
                .length = zero,
                .capacity = actual_capacity,
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

deinit #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&DynamicArray#(.t: t)
) -> () := {
    deinit(.self = $&self&.allocation)
}

copy_fallible #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: &DynamicArray#(.t: t),
) -> (.result: Errable#(.t: DynamicArray#(.t: t), .reasons: (..out_of_memory))) := {
    out :: DynamicArray#(.t: t)
    initialized ::= init#(.t: t)(.p = $&out, .allocator = allocator, .capacity = self&.length)
    if is(.value = initialized, .variant = ..error) {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    i :: UIntNative = 0
    while i < self&.length {
        ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = i).pointer
        pushed ::= push#(.t: t)(.allocator = allocator, .self = $&out, .value = ptr&)
        if is(.value = pushed, .variant = ..error) {
            deinit#(.t: t)(.allocator = allocator, .self = $&out)
            result = ..error(.reason = ..out_of_memory)
            return
        }
        i = i + 1
    }
    result = ..ok ~out
}

dynamic_array_element_ro_pointer #(.t: Type) (
    .array: &DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.pointer: &t) := {
    base ::= reinterpret_reference#(.from: UInt8, .to: t)(.base = array&.allocation.data).reference
    pointer = reference_offset#(.t: t)(.base = base, .elements = offset).reference
}

dynamic_array_element_rw_pointer #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.pointer: $&t) := {
    base ::= mutable_reinterpret_reference#(.from: UInt8, .to: t)(.base = array&.allocation.data).reference
    pointer = mutable_reference_offset#(.t: t)(.base = base, .elements = offset).reference
}

dynamic_array_grow #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .array: $&DynamicArray#(.t: t),
    .min_capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = array, .min_capacity = min_capacity)
}

-- Ensures space for at least `capacity` elements without changing length.
-- Callers that must commit an external resource after a successful capacity
-- check can follow this with `push_assume_capacity` without another OOM point.
ensure_capacity #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&DynamicArray#(.t: t),
    .capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    if self&.capacity >= capacity {
        result = ..ok Void()
        return
    }
    result = dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = self, .min_capacity = capacity)
}

dynamic_array_grow_growing #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .array: $&DynamicArray#(.t: t),
    .min_capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    element_size :: UIntNative = size_of(.type = t)
    new_capacity ::= array&.capacity
    zero :: UIntNative = 0
    one :: UIntNative = 1

    if new_capacity == zero {
        new_capacity = one
    }

    if new_capacity < min_capacity {
        new_capacity = min_capacity
    }

    new_bytes :: UIntNative = new_capacity * element_size
    allocate_result ::= allocate(.self = allocator, .size = new_bytes)
    match allocate_result {
        ..ok ~ payload {
            new_allocation ::= ~payload
            new_data ::= new_allocation.data

            if array&.length > zero {
                bytes_to_copy :: UIntNative = array&.length * element_size
                dst_view ::= array_view#(.t: UInt8)(.data = new_data, .length = bytes_to_copy)
                src_view ::= array_view#(.t: UInt8)(.data = array&.allocation.data, .length = bytes_to_copy)
                memcpy_bytes(.dst = dst_view, .src = src_view)
            }

            deinit(.self = $&array&.allocation)

            array& = (
                .allocation = ~new_allocation,
                .length = array&.length,
                .capacity = new_capacity,
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

push #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&DynamicArray#(.t: t),
    .value: t,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    one :: UIntNative = 1
    offset ::= self&.length

    if self&.length == self&.capacity {
        growth_result ::= dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = self, .min_capacity = self&.length + one)
        match growth_result {
            ..ok _ {
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
        offset = self&.length
    }

    ptr ::= dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = offset).pointer
    ptr& = value
    self&.length = offset + one
    result = ..ok Void()
}

-- Appends without allocation. The caller must first ensure `length < capacity`,
-- normally through `ensure_capacity`.
push_assume_capacity #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .value: t,
) -> () := {
    offset ::= self&.length
    ptr ::= dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = offset).pointer
    ptr& = value
    self&.length = offset + 1
}

pop #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
) -> (.value: t) := {
    one :: UIntNative = 1
    new_length ::= self&.length - one
    self&.length = new_length
    ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = new_length).pointer
    value = ptr&
}

insert #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = insert_growing#(.t: t)(.allocator = allocator, .self = self, .i = i, .value = value)
}

insert_growing #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    one :: UIntNative = 1
    current_length ::= self&.length
    element_size :: UIntNative = size_of(.type = t)

    if self&.length == self&.capacity {
        growth_result ::= dynamic_array_grow_growing#(.t: t)(.allocator = allocator, .array = self, .min_capacity = self&.length + one)
        match growth_result {
            ..ok _ {
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
        current_length = self&.length
    }

    if current_length > i {
        count_to_shift :: UIntNative = current_length - i
        bytes_to_shift :: UIntNative = count_to_shift * element_size
        temp_result ::= allocate(.self = allocator, .size = bytes_to_shift)
        match temp_result {
            ..ok ~ payload {
                temp_allocation ::= ~payload
                temp_data ::= temp_allocation.data

                source_byte_offset :: UIntNative = i * element_size
                dest_byte_offset :: UIntNative = source_byte_offset + element_size
                source_data ::= mutable_reference_offset#(.t: UInt8)(.base = self&.allocation.data, .elements = source_byte_offset).reference
                dest_data ::= mutable_reference_offset#(.t: UInt8)(.base = self&.allocation.data, .elements = dest_byte_offset).reference

                temp_view ::= array_view#(.t: UInt8)(.data = temp_data, .length = bytes_to_shift)
                source_view ::= array_view#(.t: UInt8)(.data = source_data, .length = bytes_to_shift)
                dest_view ::= array_view#(.t: UInt8)(.data = dest_data, .length = bytes_to_shift)

                memcpy_bytes(.dst = temp_view, .src = source_view)
                memcpy_bytes(.dst = dest_view, .src = temp_view)

                deinit(.self = $&temp_allocation)
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    ptr ::= dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = i).pointer
    ptr& = value
    self&.length = current_length + one
    result = ..ok Void()
}

operator get[] #(.t: Type) (
    .self: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.value: t) := {
    ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = index).pointer
    value = ptr&
}

operator get_ro_pointer[] #(.t: Type) (
    .self: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.value: &t) := {
    value = dynamic_array_element_ro_pointer#(.t: t)(.array = self, .offset = index).pointer
}

operator get_rw_pointer[] #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.value: $&t) := {
    value = dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = index).pointer
}

operator set[] #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .index: UIntNative,
    .value: t,
) -> () := {
    ptr ::= dynamic_array_element_rw_pointer#(.t: t)(.array = self, .offset = index).pointer
    ptr& = value
}

to_iterator#(.t: Type) (
    .value: &DynamicArray#(.t: t)
) -> (.iterator: DynamicArrayIterator#(.t: t)) := {
    iterator = (
        .array = value,
        .index = 0,
    )
}

to_ro_pointer_iterator#(.t: Type) (
    .value: &DynamicArray#(.t: t)
) -> (.iterator: DynamicArrayROPointerIterator#(.t: t)) := {
    iterator = (
        .array = value,
        .index = 0,
    )
}

to_rw_pointer_iterator#(.t: Type) (
    .value: $&DynamicArray#(.t: t)
) -> (.iterator: DynamicArrayRWPointerIterator#(.t: t)) := {
    iterator = (
        .array = value,
        .index = 0,
    )
}

has_next#(.t: Type) (
    .self: &DynamicArrayIterator#(.t: t)
) -> (.ok: Bool) := {
    iterator :: DynamicArrayIterator#(.t: t) = self&
    ok = iterator.index < iterator.array&.length
}

next#(.t: Type) (
    .self: $&DynamicArrayIterator#(.t: t)
) -> (.value: t) := {
    iterator :: DynamicArrayIterator#(.t: t) = self&
    current_index :: UIntNative = iterator.index
    ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = iterator.array, .offset = current_index).pointer
    value = ptr&
    self& = (
        .array = iterator.array,
        .index = current_index + 1,
    )
}

has_next#(.t: Type) (
    .self: &DynamicArrayROPointerIterator#(.t: t)
) -> (.ok: Bool) := {
    iterator :: DynamicArrayROPointerIterator#(.t: t) = self&
    ok = iterator.index < iterator.array&.length
}

next#(.t: Type) (
    .self: $&DynamicArrayROPointerIterator#(.t: t)
) -> (.value: &t) := {
    iterator :: DynamicArrayROPointerIterator#(.t: t) = self&
    current_index :: UIntNative = iterator.index
    value = dynamic_array_element_ro_pointer#(.t: t)(.array = iterator.array, .offset = current_index).pointer
    self& = (
        .array = iterator.array,
        .index = current_index + 1,
    )
}

has_next#(.t: Type) (
    .self: &DynamicArrayRWPointerIterator#(.t: t)
) -> (.ok: Bool) := {
    iterator :: DynamicArrayRWPointerIterator#(.t: t) = self&
    ok = iterator.index < iterator.array&.length
}

next#(.t: Type) (
    .self: $&DynamicArrayRWPointerIterator#(.t: t)
) -> (.value: $&t) := {
    iterator :: DynamicArrayRWPointerIterator#(.t: t) = self&
    current_index :: UIntNative = iterator.index
    value = dynamic_array_element_rw_pointer#(.t: t)(.array = iterator.array, .offset = current_index).pointer
    self& = (
        .array = iterator.array,
        .index = current_index + 1,
    )
}
