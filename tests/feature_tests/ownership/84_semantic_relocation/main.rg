Holder := (.allocation: Allocation)

implement Deinit#(Holder) (
    .deinit = (.self: $&Holder) -> () {
        deinit(.self = $&self&.allocation)
    }
)

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    result ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    replacement_result ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~payload {
            match replacement_result {
                ..error _ {
                    status_code = 1
                }
                ..ok ~replacement {
                    source :: Holder = (.allocation = ~payload)
                    destination :: Holder = (.allocation = ~replacement)
                    deinit(.self = $&destination)
                    relocate(.source = $&source, .destination = $&destination)
                    fresh ::= &destination.allocation
                    if fresh&.size != 1 {
                        status_code = 2
                        return
                    }
                    deinit(.self = $&destination)
                    status_code = 0
                }
            }
        }
    }
}
