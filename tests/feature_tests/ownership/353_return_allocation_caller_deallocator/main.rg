make := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Allocation) {
    assume error_tracer
    result = unwrap_or_abort(allocate_bytes(allocator, .size = 8, .alignment = 1))
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(system.ffi)
    allocation ::= make($&allocator)

    if allocation.size != 8 { status_code = 1 }
}
