window := (.array: $&DynamicArray<.t: UIntNative>) -> (
    .borrowed_view : MutableArrayView<.t: UIntNative>
) {
    full ::= view(.self = array)
    borrowed_view = unwrap_or_abort(
        .value = slice(.self = &full, .start = 0, .count = 1).result
    )
}

read_window := (.borrowed_view: &MutableArrayView<.t: UIntNative>) -> (.value: UIntNative) {
    value = unwrap_or_abort(.value = get(.self = borrowed_view, .index = 0).result)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    array ::= unwrap_or_abort(
        .value = DynamicArray<.t: UIntNative>(.allocator = system.page_allocator, .capacity = 2)
    )
    push_assume_capacity<.t: UIntNative> (.self = $&array, .value = 7)
    borrowed_view ::= window(.array = $&array).borrowed_view
    unwrap_or_abort(
        .value = ensure_capacity(
            .allocator = system.page_allocator, .self = $&array, .capacity = 4
        ).result
    )
    observed ::= read_window(.borrowed_view = &borrowed_view).value
    deinit(.self = $&array)
}
