main := (.system: System) -> (.status_code: Int32 = 0) {
    array ::= unwrap_or_abort(
        .value = DynamicArray<.t: UIntNative>(.allocator = system.page_allocator, .capacity = 4)
    )
    push_assume_capacity<.t: UIntNative> (.self = $&array, .value = 7)
    element ::= unwrap_or_abort(
        .value = get_mutable_reference(.self = $&array, .index = 0).result
    )
    removed ::= unwrap_or_abort(.value = remove(.self = $&array, .index = 0).result)
    element&= 3
    deinit(.self = $&array)
}
