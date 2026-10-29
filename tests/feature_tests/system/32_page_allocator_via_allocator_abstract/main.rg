alloc_one := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(.t: UIntNative, .reasons: (..out_of_memory))) {
    assume error_tracer

    assume allocator

    allocated ::= allocate_bytes(.self = allocator, .size = 1)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~payload {
            allocation ::= ~payload
            result = ..ok allocation.data.address
            deinit(.self = $&allocation)
        }
    }
}

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage :: PageAllocator = PageAllocator(.memory = system.memory)
    assume allocator ::= $&allocator_storage
    allocated ::= alloc_one(.allocator = $&allocator_storage)
    if is(.value = allocated, .variant = ..error) {
        status_code = 2
        return
    }
    addr ::= allocated ..ok

    if addr == 0 {
        status_code = 1
        return
    }

    status_code = 0
}
