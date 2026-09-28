main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    source_result ::= allocate(.self = $&allocator_storage, .size = 1)
    destination_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ source_payload {
            match destination_result {
                ..error _ { status_code = 1 }
                ..ok ~ destination_payload {
                    source :: Allocation = ~source_payload
                    destination :: Allocation = ~destination_payload
                    relocate(.source = $&source, .destination = $&destination)
                    status_code = 0
                }
            }
        }
    }
}
