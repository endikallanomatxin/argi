make := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator    : $&AllocatorType,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) {
    assume error_tracer

    assume allocator

    result = allocate_bytes(.self = allocator, .size = 1)
}

main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    result ::= make(.allocator = $&allocator_storage)
    match result {
        ..error _ {
            status_code = 1
        }
        ..ok ~payload {
            allocation ::= ~payload
            duplicate ::= ~payload
            deinit(.self = $&allocation)
            deinit(.self = $&duplicate)
            status_code = 0
        }
    }
}
