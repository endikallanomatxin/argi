main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~payload {
            allocation ::= ~payload
            byte ::= allocation.data&
            deinit(.self = $&allocation)
            if byte == 0 {
                status_code = 0
            } else {
                status_code = 1
            }
        }
    }
}
