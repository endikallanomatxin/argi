move_between := #(.t: Type) (.source: $&t, .destination: $&t) -> () {
    relocate(.source = source, .destination = destination)
}

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
                    source ::= ~payload
                    destination ::= ~replacement
                    deinit(.self = $&destination)
                    move_between(.source = $&source, .destination = $&destination)
                    deinit(.self = $&destination)
                    status_code = 0
                }
            }
        }
    }
}
