main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            byte ::= _trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference
            byte& = 1
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
}
