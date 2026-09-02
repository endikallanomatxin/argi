ArrayIterator#(.n: UIntNative, .t: Type) : Type = (
    .array : &Array#(.n = n, .t: t)
    .index : UIntNative
)

ArrayROPointerIterator#(.n: UIntNative, .t: Type) : Type = (
    .array : &Array#(.n = n, .t: t)
    .index : UIntNative
)

ArrayRWPointerIterator#(.n: UIntNative, .t: Type) : Type = (
    .array : $&Array#(.n = n, .t: t)
    .index : UIntNative
)

ArrayIterator#(.n: UIntNative, .t: Type) implements Iterator#(.t: t)
ArrayROPointerIterator#(.n: UIntNative, .t: Type) implements Iterator#(.t: &t)
ArrayRWPointerIterator#(.n: UIntNative, .t: Type) implements Iterator#(.t: $&t)
Array#(.n: UIntNative, .t: Type) implements Iterable#(.t: t)
Array#(.n: UIntNative, .t: Type) implements ROPointerIterable#(.t: t)
Array#(.n: UIntNative, .t: Type) implements RWPointerIterable#(.t: t)

to_iterator#(.n: UIntNative, .t: Type) (
    .value: &Array#(.n = n, .t: t)
) -> (.iterator: ArrayIterator#(.n = n, .t: t)) := {
    iterator = (
        .array = value,
        .index = 0,
    )
}

to_ro_pointer_iterator#(.n: UIntNative, .t: Type) (
    .value: &Array#(.n = n, .t: t)
) -> (.iterator: ArrayROPointerIterator#(.n = n, .t: t)) := {
    iterator = (
        .array = value,
        .index = 0,
    )
}

to_rw_pointer_iterator#(.n: UIntNative, .t: Type) (
    .value: $&Array#(.n = n, .t: t)
) -> (.iterator: ArrayRWPointerIterator#(.n = n, .t: t)) := {
    iterator = (
        .array = value,
        .index = 0,
    )
}

has_next#(.n: UIntNative, .t: Type) (
    .self: &ArrayIterator#(.n = n, .t: t)
) -> (.ok: Bool) := {
    ok = self&.index < n
}

next#(.n: UIntNative, .t: Type: ImplicitlyCopyable) (
    .self: $&ArrayIterator#(.n = n, .t: t)
) -> (.value: t) := {
    current_index :: UIntNative = self&.index
    value = self&.array&[current_index]
    self&.index = current_index + 1
}

has_next#(.n: UIntNative, .t: Type) (
    .self: &ArrayROPointerIterator#(.n = n, .t: t)
) -> (.ok: Bool) := {
    ok = self&.index < n
}

next#(.n: UIntNative, .t: Type) (
    .self: $&ArrayROPointerIterator#(.n = n, .t: t)
) -> (.value: &t) := {
    current_index :: UIntNative = self&.index
    base ::= reinterpret_reference#(.from: Array#(.n = n, .t: t), .to: t)(.base = self&.array).reference
    value = reference_offset#(.t: t)(.base = base, .elements = current_index).reference
    self&.index = current_index + 1
}

has_next#(.n: UIntNative, .t: Type) (
    .self: &ArrayRWPointerIterator#(.n = n, .t: t)
) -> (.ok: Bool) := {
    ok = self&.index < n
}

next#(.n: UIntNative, .t: Type) (
    .self: $&ArrayRWPointerIterator#(.n = n, .t: t)
) -> (.value: $&t) := {
    current_index :: UIntNative = self&.index
    base ::= mutable_reinterpret_reference#(.from: Array#(.n = n, .t: t), .to: t)(.base = self&.array).reference
    value = mutable_reference_offset#(.t: t)(.base = base, .elements = current_index).reference
    self&.index = current_index + 1
}
