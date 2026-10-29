main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    array ::= unwrap_or_abort(
        .value = DynamicArray#(.t: UIntNative)(
            .allocator = system.page_allocator, .capacity = 4
        )
    )
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    element ::= _trusted_dynamic_array_element_reference#(.t: UIntNative)(
        .array = &array, .offset = 0
    ).pointer

    observed ::= element&
    deinit(.self = $&array)
}
