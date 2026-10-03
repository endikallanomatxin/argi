main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    arena :: ArenaAllocator
    initialized ::= ArenaAllocator(.allocator = $&allocator_storage)
    match initialized {
        ..ok ~constructed_value { arena = ~constructed_value }
        ..error _ {
        status_code = 1
        return
    }
    }
    allocated ::= allocate(.self = $&arena, .size = 8, .alignment = 3)
    match allocated {
        ..error _ { status_code = 2 }
        ..ok ~ payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
    deinit(.self = $&arena)
}
