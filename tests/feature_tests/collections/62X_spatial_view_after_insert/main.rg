window := (.array: $&DynamicArray#(.t: UIntNative), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .borrowed_view : MutableArrayView#(.t: UIntNative)
) {
    assume error_tracer
    full ::= view(.self = array)
    borrowed_view = unwrap_or_abort(
        .value = slice(.self = &full, .start = 0, .count = 1).result
    )
}

read_window := (
    .borrowed_view: &MutableArrayView#(.t: UIntNative), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.value: UIntNative) {
    assume error_tracer
    value = unwrap_or_abort(.value = get(.self = borrowed_view, .index = 0).result)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    array ::= unwrap_or_abort(
        .value = DynamicArray#(.t: UIntNative)(
            .allocator = system.page_allocator, .capacity = 2
        )
    )
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    borrowed_view ::= window(.array = $&array).borrowed_view
    unwrap_or_abort(
        .value = insert(
            .allocator = system.page_allocator, .self = $&array, .index = 0, .value = 9
        ).result
    )
    observed ::= read_window(.borrowed_view = &borrowed_view).value
    deinit(.self = $&array)
}
