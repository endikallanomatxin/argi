main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .metadata_allocator = system.allocator)
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
