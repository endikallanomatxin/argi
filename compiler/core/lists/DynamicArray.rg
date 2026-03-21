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
    --
    -- TODO: Revisit whether this iterator should store `&DynamicArray#(.t: t)`
    -- directly once generic pointer handling in the checker is strong enough.
    -- For now it keeps the flattened runtime state because the direct pointer
    -- representation currently trips generic type checking.
    --
    .data   : $&UInt8
    .length : UIntNative
    .index  : UIntNative
)

Iterator#(.t: Type) canbe DynamicArrayIterator#(.t: t)

init #(.t: Type) (
    .p: $&DynamicArray#(.t: t),
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
        .allocation = allocation_init(.size = bytes),
        .length = zero,
        .capacity = actual_capacity,
    )
}

deinit #(.t: Type) (.self: $&DynamicArray#(.t: t)) -> () := {
    zero :: UIntNative = 0
    allocation_deinit(.allocation = self&.allocation)
    self& = (
        .allocation = self&.allocation,
        .length = zero,
        .capacity = zero,
    )
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
    new_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = new_bytes))
    old_addr :: UIntNative = cast#(.to: UIntNative)(.value = array&.allocation.data)

    if array&.length > zero {
        bytes_to_copy :: UIntNative = array&.length * element_size
        memcpy(
            .dst = cast#(.to: $&Any)(.value = new_addr),
            .src = cast#(.to: &Any)(.value = old_addr),
            .n = bytes_to_copy,
        )
    }

    free(.pointer = cast#(.to: &Any)(.value = old_addr))

    array& = (
        .allocation = (
            .data = cast#(.to: $&UInt8)(.value = new_addr),
            .size = new_bytes,
        ),
        .length = array&.length,
        .capacity = new_capacity,
    )
}

push #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .value: t,
) -> () := {
    one :: UIntNative = 1
    offset ::= self&.length

    if self&.length == self&.capacity {
        dynamic_array_grow#(.t: t)(.array = self, .min_capacity = self&.length + one)
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
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> () := {
    one :: UIntNative = 1
    current_length ::= self&.length
    element_size :: UIntNative = size_of(.type = t)

    if self&.length == self&.capacity {
        dynamic_array_grow#(.t: t)(.array = self, .min_capacity = self&.length + one)
        current_length = self&.length
    }

    if current_length > i {
        count_to_shift :: UIntNative = current_length - i
        bytes_to_shift :: UIntNative = count_to_shift * element_size
        temp_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = bytes_to_shift))

        source_addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = self, .offset = i).address
        dest_addr ::= source_addr + element_size

        memcpy(
            .dst = cast#(.to: $&Any)(.value = temp_addr),
            .src = cast#(.to: &Any)(.value = source_addr),
            .n = bytes_to_shift,
        )

        memcpy(
            .dst = cast#(.to: $&Any)(.value = dest_addr),
            .src = cast#(.to: &Any)(.value = temp_addr),
            .n = bytes_to_shift,
        )

        free(.pointer = cast#(.to: &Any)(.value = temp_addr))
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
        .data = value&.allocation.data,
        .length = value&.length,
        .index = 0,
    )
}

has_next#(.t: Type) (
    .self: &DynamicArrayIterator#(.t: t)
) -> (.ok: Bool) := {
    iterator :: DynamicArrayIterator#(.t: t) = self&
    ok = iterator.index < iterator.length
}

next#(.t: Type) (
    .self: $&DynamicArrayIterator#(.t: t)
) -> (.value: t) := {
    iterator :: DynamicArrayIterator#(.t: t) = self&
    current_index :: UIntNative = iterator.index
    element_size :: UIntNative = size_of(.type = t)
    base :: UIntNative = cast#(.to: UIntNative)(.value = iterator.data)
    addr :: UIntNative = base + current_index * element_size
    ptr : &t = cast#(.to: &t)(.value = addr)
    value = ptr&
    self& = (
        .data = iterator.data,
        .length = iterator.length,
        .index = current_index + 1,
    )
}
