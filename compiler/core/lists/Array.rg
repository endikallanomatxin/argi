ArrayIterator#(.n: UIntNative, .t: Type) : Type = (
    .array : &Array#(.n = n, .t: t)
    .index : UIntNative
)

Iterator#(.t: Type, .n: UIntNative) canbe ArrayIterator#(.n = n, .t: t)
Iterable#(.t: Type, .n: UIntNative) canbe Array#(.n = n, .t: t)

to_iterator#(.n: UIntNative, .t: Type) (
    .value: &Array#(.n = n, .t: t)
) -> (.iterator: ArrayIterator#(.n = n, .t: t)) := {
    iterator = (
        .array = value,
        .index = 0,
    )
}

has_next#(.n: UIntNative, .t: Type) (
    .self: &ArrayIterator#(.n = n, .t: t)
) -> (.ok: Bool) := {
    iterator :: ArrayIterator#(.n = n, .t: t) = self&
    ok = iterator.index < n
}

next#(.n: UIntNative, .t: Type) (
    .self: $&ArrayIterator#(.n = n, .t: t)
) -> (.value: t) := {
    iterator :: ArrayIterator#(.n = n, .t: t) = self&
    current_index :: UIntNative = iterator.index
    array :: &Array#(.n = n, .t: t) = iterator.array
    array_value :: Array#(.n = n, .t: t) = array&
    value = array_value[current_index]
    self& = (
        .array = iterator.array,
        .index = current_index + 1,
    )
}
