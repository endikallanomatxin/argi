-- Exchange copied values through indexed references without resizing storage.
_swap_indexed_values := #(
    .t: Type: ImplicitlyCopyable, .Collection: Type: MutableIndexable#(.Item: t)
) (.self: $&Collection, .left: UIntNative, .right: UIntNative) -> () {
    if left == right { return }
    left_ref ::= unwrap_or_abort(.value = get_mutable_reference(self, .index = left))
    right_ref ::= unwrap_or_abort(.value = get_mutable_reference(self, .index = right))
    saved ::= left_ref&
    left_ref&= right_ref&
    right_ref&= saved
}

reverse := #(.t: Type: ImplicitlyCopyable, .Collection: Type: MutableIndexable#(.Item: t)) (
    .self : $&Collection
) -> () {
    left :: UIntNative = 0
    end ::= length(self).count

    while left < end {
        end = end - 1
        if left >= end { return }
        _swap_indexed_values#(.t: t)(self, .left = left, .right = end)
        left = left + 1
    }
}
