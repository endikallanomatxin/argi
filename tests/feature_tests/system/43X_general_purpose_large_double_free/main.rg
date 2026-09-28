main(.system: System) -> (.status_code: Int32) := {
    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator, .size = 5000, .alignment = 4096)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            data ::= allocation.data
            deinit(.self = $&allocation)
            deallocate(.self = $&allocator, .data = data, .size = 5000, .alignment = 4096)
            status_code = 0
        }
    }
}
