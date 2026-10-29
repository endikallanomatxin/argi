escape := (.ffi: $&ForeignFunctionInterface, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Allocation
) {
    assume error_tracer
    allocator ::= CAllocator(ffi)
    result = unwrap_or_abort(allocate_bytes($&allocator, .size = 8, .alignment = 1))
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    allocation ::= escape(system.ffi)
}
