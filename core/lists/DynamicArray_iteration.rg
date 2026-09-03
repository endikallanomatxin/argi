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

DynamicArrayIterator#(.t: Type: ImplicitlyCopyable) implements Iterator#(.t: t)
DynamicArrayROPointerIterator#(.t: Type) implements Iterator#(.t: &t)
DynamicArrayRWPointerIterator#(.t: Type) implements Iterator#(.t: $&t)
DynamicArray#(.t: Type: ImplicitlyCopyable) implements Iterable#(.t: t)
DynamicArray#(.t: Type) implements ROPointerIterable#(.t: t)
DynamicArray#(.t: Type) implements RWPointerIterable#(.t: t)

to_iterator#(.t: Type: ImplicitlyCopyable) (
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

has_next#(.t: Type: ImplicitlyCopyable) (
    .self: &DynamicArrayIterator#(.t: t)
) -> (.ok: Bool) := {
    ok = self&.index < self&.array&.length
}

next#(.t: Type: ImplicitlyCopyable) (
    .self: $&DynamicArrayIterator#(.t: t)
) -> (.value: t) := {
    -- Value iteration is the array's conditional implicit-copy capability.
    current_index :: UIntNative = self&.index
    ptr ::= dynamic_array_element_ro_pointer#(.t: t)(.array = self&.array, .offset = current_index).pointer
    value = ptr&
    self&.index = current_index + 1
}

has_next#(.t: Type) (
    .self: &DynamicArrayROPointerIterator#(.t: t)
) -> (.ok: Bool) := {
    ok = self&.index < self&.array&.length
}

next#(.t: Type) (
    .self: $&DynamicArrayROPointerIterator#(.t: t)
) -> (.value: &t) := {
    current_index :: UIntNative = self&.index
    value = dynamic_array_element_ro_pointer#(.t: t)(.array = self&.array, .offset = current_index).pointer
    self&.index = current_index + 1
}

has_next#(.t: Type) (
    .self: &DynamicArrayRWPointerIterator#(.t: t)
) -> (.ok: Bool) := {
    ok = self&.index < self&.array&.length
}

next#(.t: Type) (
    .self: $&DynamicArrayRWPointerIterator#(.t: t)
) -> (.value: $&t) := {
    current_index :: UIntNative = self&.index
    value = dynamic_array_element_rw_pointer#(.t: t)(.array = self&.array, .offset = current_index).pointer
    self&.index = current_index + 1
}
