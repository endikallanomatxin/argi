bad := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : $&GeneralPurposeAllocator
) {
    assume error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    result = allocator
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= bad(.system = system).result
}
