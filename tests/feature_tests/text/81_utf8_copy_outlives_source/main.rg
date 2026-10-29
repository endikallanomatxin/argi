copy_local := (
    .allocator    : $&PageAllocator,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(String, (..invalid_utf8, ..out_of_memory))) {
    assume error_tracer

    bytes: [2]UInt8 = (195, 169)
    result = string_from_bytes(.bytes = view(&bytes), .allocator = allocator)
}

main := (.system: System) -> () {
    text ::= unwrap_or_abort(.value = copy_local(.allocator = system.page_allocator))
    if view(&text) != "é" { abort }
}
