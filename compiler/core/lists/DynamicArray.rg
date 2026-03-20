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

init #(.t: Type) (
    .p: $&DynamicArray#(.t: t),
    .capacity: UIntNative,
) -> () := {
    dynamic_array_init#(.t: t)(.array = p, .capacity = capacity)
}

dynamic_array_init #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .capacity: UIntNative,
) -> () := {
    element_size :: UIntNative = size_of(.type = t)
    actual_capacity ::= capacity
    zero :: UIntNative = 0
    one :: UIntNative = 1
    snapshot :: DynamicArray#(.t: t) = array&

    if actual_capacity == zero {
        actual_capacity = one
    }

    bytes :: UIntNative = actual_capacity * element_size
    snapshot.allocation = allocation_init(.size = bytes)
    snapshot.length = zero
    snapshot.capacity = actual_capacity
    array& = snapshot
}

dynamic_array_deinit #(.t: Type) (.array: $&DynamicArray#(.t: t)) -> () := {
    zero :: UIntNative = 0
    snapshot :: DynamicArray#(.t: t) = array&
    allocation_deinit(.allocation = snapshot.allocation)
    snapshot.length = zero
    snapshot.capacity = zero
    array& = snapshot
}

dynamic_array_element_address #(.t: Type) (
    .array: &DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.address: UIntNative) := {
    element_size :: UIntNative = size_of(.type = t)
    snapshot :: DynamicArray#(.t: t) = array&
    base :: UIntNative = cast#(.to: UIntNative)(.value = snapshot.allocation.data)
    address = base + offset * element_size
}

dynamic_array_get #(.t: Type) (
    .array: &DynamicArray#(.t: t),
    .offset: UIntNative,
) -> (.value: t) := {
    addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = array, .offset = offset).address
    ptr : &t = cast#(.to: &t)(.value = addr)
    value = ptr&
}

dynamic_array_set #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .offset: UIntNative,
    .value: t,
) -> () := {
    snapshot :: DynamicArray#(.t: t) = array&
    addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = &snapshot, .offset = offset).address
    ptr : $&t = cast#(.to: $&t)(.value = addr)
    ptr& = value
}

dynamic_array_grow #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .min_capacity: UIntNative,
) -> () := {
    element_size :: UIntNative = size_of(.type = t)
    snapshot :: DynamicArray#(.t: t) = array&
    new_capacity ::= snapshot.capacity
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
    old_addr :: UIntNative = cast#(.to: UIntNative)(.value = snapshot.allocation.data)

    if snapshot.length > zero {
        bytes_to_copy :: UIntNative = snapshot.length * element_size
        memcpy(
            .dst = cast#(.to: $&Any)(.value = new_addr),
            .src = cast#(.to: &Any)(.value = old_addr),
            .n = bytes_to_copy,
        )
    }

    free(.pointer = cast#(.to: &Any)(.value = old_addr))

    snapshot.allocation = (
        .data = cast#(.to: $&UInt8)(.value = new_addr),
        .size = new_bytes,
    )
    snapshot.capacity = new_capacity
    array& = snapshot
}

dynamic_array_push #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .value: t,
) -> () := {
    one :: UIntNative = 1
    snapshot :: DynamicArray#(.t: t) = array&
    offset ::= snapshot.length

    if snapshot.length == snapshot.capacity {
        dynamic_array_grow#(.t: t)(.array = array, .min_capacity = snapshot.length + one)
        grown_snapshot :: DynamicArray#(.t: t) = array&
        offset = grown_snapshot.length
    }

    dynamic_array_set#(.t: t)(.array = array, .offset = offset, .value = value)

    final_snapshot :: DynamicArray#(.t: t) = array&
    final_snapshot.length = offset + one
    array& = final_snapshot
}

dynamic_array_pop #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
) -> (.value: t) := {
    one :: UIntNative = 1
    snapshot :: DynamicArray#(.t: t) = array&
    new_length ::= snapshot.length - one
    snapshot.length = new_length
    array& = snapshot
    updated_snapshot :: DynamicArray#(.t: t) = array&
    value = dynamic_array_get#(.t: t)(.array = &updated_snapshot, .offset = new_length).value
}

dynamic_array_insert #(.t: Type) (
    .array: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> () := {
    one :: UIntNative = 1
    initial_snapshot :: DynamicArray#(.t: t) = array&
    current_length ::= initial_snapshot.length
    element_size :: UIntNative = size_of(.type = t)

    if initial_snapshot.length == initial_snapshot.capacity {
        dynamic_array_grow#(.t: t)(.array = array, .min_capacity = initial_snapshot.length + one)
        grown_snapshot :: DynamicArray#(.t: t) = array&
        current_length = grown_snapshot.length
    }

    if current_length > i {
        count_to_shift :: UIntNative = current_length - i
        bytes_to_shift :: UIntNative = count_to_shift * element_size
        temp_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = bytes_to_shift))

        shift_snapshot :: DynamicArray#(.t: t) = array&
        source_addr :: UIntNative = dynamic_array_element_address#(.t: t)(.array = &shift_snapshot, .offset = i).address
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

    dynamic_array_set#(.t: t)(.array = array, .offset = i, .value = value)

    final_snapshot :: DynamicArray#(.t: t) = array&
    final_snapshot.length = current_length + one
    array& = final_snapshot
}

push #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .value: t,
) -> () := {
    dynamic_array_push#(.t: t)(.array = self, .value = value)
}

pop #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
) -> (.value: t) := {
    value = dynamic_array_pop#(.t: t)(.array = self).value
}

insert #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .i: UIntNative,
    .value: t,
) -> () := {
    dynamic_array_insert#(.t: t)(.array = self, .i = i, .value = value)
}

operator get[] #(.t: Type) (
    .self: &DynamicArray#(.t: t),
    .index: UIntNative,
) -> (.value: t) := {
    value = dynamic_array_get#(.t: t)(.array = self, .offset = index).value
}

operator set[] #(.t: Type) (
    .self: $&DynamicArray#(.t: t),
    .index: UIntNative,
    .value: t,
) -> () := {
    dynamic_array_set#(.t: t)(.array = self, .offset = index, .value = value)
}
