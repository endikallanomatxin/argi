make := #(.t: Type) (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: t) {
    assume error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    text ::= unwrap_or_abort(.value = string_with_capacity(.capacity = 8))
    result = 7
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    text ::= unwrap_or_abort(.value = string_with_capacity(.capacity = 8))
    if byte_length(&text).count != 0 { status_code = 1 }
    if make#(.t: Int32)(.system = system).result != 7 { status_code = 2 }
}
