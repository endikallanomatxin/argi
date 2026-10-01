-- Exchange copied values through indexed references without resizing storage.
_swap_indexed_values#(.t: Type: ImplicitlyCopyable)(
    .self: $&IndexableMutable#(.t: t),
    .left: UIntNative,
    .right: UIntNative,
) -> () := {
    if left == right { return }
    left_ref ::= unwrap_or_abort(.value = get_rw_ref(.self = self, .index = left))
    right_ref ::= unwrap_or_abort(.value = get_rw_ref(.self = self, .index = right))
    saved ::= left_ref&
    left_ref& = right_ref&
    right_ref& = saved
}

reverse#(.t: Type: ImplicitlyCopyable)(
    .self: $&IndexableMutable#(.t: t),
) -> () := {
    left :: UIntNative = 0
    end ::= length(.self = self).count
    while left < end {
        end = end - 1
        if left >= end { return }
        _swap_indexed_values#(.t: t)(.self = self, .left = left, .right = end)
        left = left + 1
    }
}
