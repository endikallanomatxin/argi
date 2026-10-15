main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(
        .value = DynamicArray#(.t: UIntNative)(
            .allocator = system.page_allocator, .capacity = 2
        )
    )
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    borrowed_view ::= view(.array = $&array)
    element ::= unwrap_or_abort(
        .value = get_reference(.self = &borrowed_view, .index = 0).result
    )
    removed ::= unwrap_or_abort(.value = pop(.self = $&array).result)
    observed ::= element&
    deinit(.self = $&array)
}
