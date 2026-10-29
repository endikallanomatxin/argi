make := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator    : $&AllocatorType,
    .condition    : Bool,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) {
    assume error_tracer

    assume allocator

    if condition {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    result = allocate_bytes(.self = allocator, .size = 1)
}

main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    failed ::= make(.allocator = $&allocator_storage, .condition = true)
    match failed {
        ..error _ {
            status_code = 0
        }
        ..ok ~payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
            status_code = 1
        }
    }

    succeeded ::= make(.allocator = $&allocator_storage, .condition = false)
    match succeeded {
        ..error _ {
            status_code = 2
        }
        ..ok ~payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
        }
    }
}
