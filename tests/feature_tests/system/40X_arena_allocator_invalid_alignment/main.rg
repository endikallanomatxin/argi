main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .backing_allocator = $&allocator_storage)
    if is(.value = initialized, .variant = ..error) {
        status_code = 1
        return
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
