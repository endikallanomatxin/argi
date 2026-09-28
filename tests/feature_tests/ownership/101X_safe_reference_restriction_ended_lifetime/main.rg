unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    source_result ::= allocate(.self = $&allocator_storage, .size = 1)
    lifetime_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ source_payload {
            match lifetime_result {
                ..error _ { status_code = 2 }
                ..ok ~ lifetime_payload {
                    source ::= ~source_payload
                    lifetime ::= ~lifetime_payload
                    restricted ::= restrict_reference#(.t: $&UInt8)(.input = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&source, .offset = 0).reference, .on = &lifetime).reference
                    deinit(.self = $&lifetime)
                    if restricted& == 0 {
                        status_code = 0
                    } else {
                        status_code = 1
                    }
                    deinit(.self = $&source)
                }
            }
        }
    }
}
