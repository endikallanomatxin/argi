window := (.array: $&DynamicArray#(.t: UIntNative), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .borrowed_view : ArrayView#(.t: UIntNative)
) {
    assume error_tracer
    full ::= view(.self = array)
    part ::= unwrap_or_abort(.value = slice(.self = &full, .start = 0, .count = 1).result)
    borrowed_view = as_readonly(&part)
}

read_window := (
    .borrowed_view: &ArrayView#(.t: UIntNative), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.value: UIntNative) {
    assume error_tracer
    element ::= unwrap_or_abort(
        .value = get_reference(.self = borrowed_view, .index = 0).result
    )
    value = element&
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
    removed ::= unwrap_or_abort(.value = remove(.self = $&array, .index = 0).result)
    observed ::= read_window(.borrowed_view = &borrowed_view).value
    deinit(.self = $&array)
}
