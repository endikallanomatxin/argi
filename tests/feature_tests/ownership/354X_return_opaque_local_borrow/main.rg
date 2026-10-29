escape := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: DynamicArray#(&Int32)) {
    assume error_tracer
    assume allocator
    array ::= unwrap_or_abort(DynamicArray#(&Int32)(.capacity = 1))
    local :: Int32 = 7

    push_assume_capacity($&array, &local)
    result = ~array
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= GeneralPurposeAllocator(system.page_allocator)
    escaped ::= escape($&allocator)
}
