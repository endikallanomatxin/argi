main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
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
