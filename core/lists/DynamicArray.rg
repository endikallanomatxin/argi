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

DynamicArrayIterator#(.t: Type) implements Iterator#(.t: t)
DynamicArray#(.t: Type) implements Iterable#(.t: t)

init #(.t: Type) (
    .p: $&DynamicArray#(.t: t),
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .capacity: UIntNative,
) -> () := {
    element_size :: UIntNative = size_of(.type = t)
    actual_capacity ::= capacity
    zero :: UIntNative = 0
    one :: UIntNative = 1

    if actual_capacity == zero {
        actual_capacity = one
    }

    bytes :: UIntNative = actual_capacity * element_size
    p& = (
        .allocation = (
            .data = allocate(.self = allocator, .size = bytes),
            .size = bytes,
        ),
        .length = zero,
        .capacity = actual_capacity,
    )
}

deinit #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&DynamicArray#(.t: t)
) -> () := {
    zero :: UIntNative = 0
    deallocate(.self = allocator, .data = self&.allocation.data, .size = self&.allocation.size)
    self& = (
        .allocation = self&.allocation,
        .length = zero,
        .capacity = zero,
    )
}

copy #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: DynamicArray#(.t: t),
) -> (.out: DynamicArray#(.t: t)) := {
    init#(.t: t)(.p = $&out, .allocator = allocator, .capacity = self.length)

    i :: UIntNative = 0
    while i < self.length {
        addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = &self, .offset = i).address
        ptr : &t = cast#(.to: &t)(.value = addr)
        push#(.t: t)(.allocator = allocator, .self = $&out, .value = ptr&)
        i = i + 1
    }
}

dynamic_array_element_address #(.t: Type) (
    .array: &DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.address: UIntNative) := {
    element_size :: UIntNative = size_of(.type = t)
    base :: UIntNative = cast#(.to: UIntNative)(.value = array&.allocation.data)
    address = base + offset * element_size
}

dynamic_array_grow #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .array: $&DynamicArray#(.t: t),
    .min_capacity: UIntNative,
) -> () := {
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
    new_data ::= allocate(.self = allocator, .size = new_bytes)

    if array&.length > zero {
        bytes_to_copy :: UIntNative = array&.length * element_size
        dst_view ::= array_view#(.t: UInt8)(.data = new_data, .length = bytes_to_copy)
        src_view ::= array_view#(.t: UInt8)(.data = array&.allocation.data, .length = bytes_to_copy)
        memcpy_bytes(.dst = dst_view, .src = src_view)
    }

    deallocate(.self = allocator, .data = array&.allocation.data, .size = array&.allocation.size)

    array& = (
        .allocation = (
            .data = new_data,
            .size = new_bytes,
        ),
        .length = array&.length,
        .capacity = new_capacity,
    )
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
    allocate_result ::= allocate_fallible(.self = allocator, .size = new_bytes)
    match allocate_result {
        ..ok payload {
            new_data : $&UInt8 = cast#(.to: $&UInt8)(.value = payload)

            if array&.length > zero {
                bytes_to_copy :: UIntNative = array&.length * element_size
                dst_view ::= array_view#(.t: UInt8)(.data = new_data, .length = bytes_to_copy)
                src_view ::= array_view#(.t: UInt8)(.data = array&.allocation.data, .length = bytes_to_copy)
                memcpy_bytes(.dst = dst_view, .src = src_view)
            }

            deallocate(.self = allocator, .data = array&.allocation.data, .size = array&.allocation.size)

            array& = (
                .allocation = (
                    .data = new_data,
                    .size = new_bytes,
                ),
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

    ptr_addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = offset).address
    ptr : $&t = cast#(.to: $&t)(.value = ptr_addr)
    ptr& = value
    self& = (
        .allocation = self&.allocation,
        .length = offset + one,
        .capacity = self&.capacity,
    )
    result = ..ok Void()
}

pop #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
) -> (.value: t) := {
    one :: UIntNative = 1
    new_length ::= self&.length - one
    self& = (
        .allocation = self&.allocation,
        .length = new_length,
        .capacity = self&.capacity,
    )
    addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = new_length).address
    ptr : &t = cast#(.to: &t)(.value = addr)
    value = ptr&
}

insert #(.t: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> () := {
    one :: UIntNative = 1
    current_length ::= self&.length
    element_size :: UIntNative = size_of(.type = t)

    if self&.length == self&.capacity {
        dynamic_array_grow#(.t: t)(.allocator = allocator, .array = self, .min_capacity = self&.length + one)
        current_length = self&.length
    }

    if current_length > i {
        count_to_shift :: UIntNative = current_length - i
        bytes_to_shift :: UIntNative = count_to_shift * element_size
        temp_data ::= allocate(.self = allocator, .size = bytes_to_shift)
        temp_addr :: UIntNative = cast#(.to: UIntNative)(.value = temp_data)

        source_addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = i).address
        dest_addr ::= source_addr + element_size

        temp_view ::= array_view#(.t: UInt8)(.data = temp_data, .length = bytes_to_shift)
        source_view ::= array_view_from_address#(.t: UInt8)(.address = source_addr, .length = bytes_to_shift)
        dest_view ::= array_view_from_address#(.t: UInt8)(.address = dest_addr, .length = bytes_to_shift)

        memcpy_bytes(.dst = temp_view, .src = source_view)
        memcpy_bytes(.dst = dest_view, .src = temp_view)

        deallocate(.self = allocator, .data = temp_data, .size = bytes_to_shift)
    }

    ptr_addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = i).address
    ptr : $&t = cast#(.to: $&t)(.value = ptr_addr)
    ptr& = value
    self& = (
        .allocation = self&.allocation,
        .length = current_length + one,
        .capacity = self&.capacity,
    )
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
        temp_result ::= allocate_fallible(.self = allocator, .size = bytes_to_shift)
        match temp_result {
            ..ok payload {
                temp_data : $&UInt8 = cast#(.to: $&UInt8)(.value = payload)

                source_addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = i).address
                dest_addr ::= source_addr + element_size

                temp_view ::= array_view#(.t: UInt8)(.data = temp_data, .length = bytes_to_shift)
                source_view ::= array_view_from_address#(.t: UInt8)(.address = source_addr, .length = bytes_to_shift)
                dest_view ::= array_view_from_address#(.t: UInt8)(.address = dest_addr, .length = bytes_to_shift)

                memcpy_bytes(.dst = temp_view, .src = source_view)
                memcpy_bytes(.dst = dest_view, .src = temp_view)

                deallocate(.self = allocator, .data = temp_data, .size = bytes_to_shift)
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    ptr_addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = i).address
    ptr : $&t = cast#(.to: $&t)(.value = ptr_addr)
    ptr& = value
    self& = (
        .allocation = self&.allocation,
        .length = current_length + one,
        .capacity = self&.capacity,
    )
    result = ..ok Void()
}

operator get[] #(.t: Type) (
    .self: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.value: t) := {
    addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = index).address
    ptr : &t = cast#(.to: &t)(.value = addr)
    value = ptr&
}

operator set[] #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .index: UIntNative,
    .value: t,
) -> () := {
    addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = index).address
    ptr : $&t = cast#(.to: $&t)(.value = addr)
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
    addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = iterator.array, .offset = current_index).address
    ptr : &t = cast#(.to: &t)(.value = addr)
    value = ptr&
    self& = (
        .array = iterator.array,
        .index = current_index + 1,
    )
}
