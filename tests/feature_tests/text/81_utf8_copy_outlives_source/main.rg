copy_local := (.allocator: $&PageAllocator, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(String, (..invalid_utf8, ..out_of_memory))
) {
    assume error_tracer

    bytes: [2]UInt8 = (195, 169)
    result = string_from_bytes(.bytes = view(&bytes), .allocator = allocator)
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    text ::= unwrap_or_abort(.value = copy_local(.allocator = system.page_allocator))
    if view(&text) != "é" { abort }
}
