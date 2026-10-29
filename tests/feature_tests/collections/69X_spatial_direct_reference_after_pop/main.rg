main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    array ::= unwrap_or_abort(
        .value = DynamicArray#(.t: UIntNative)(
            .allocator = system.page_allocator, .capacity = 4
        )
    )
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    element ::= unwrap_or_abort(.value = get_reference(.self = &array, .index = 0).result)
    removed ::= unwrap_or_abort(.value = pop(.self = $&array).result)
    observed ::= element&
    deinit(.self = $&array)
}
