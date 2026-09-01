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
    -- The value iterator copies; owning iteration remains reference-only.
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
