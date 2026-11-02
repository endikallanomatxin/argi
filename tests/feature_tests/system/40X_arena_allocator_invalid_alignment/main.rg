main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator
    arena :: ArenaAllocator
    initialized ::= ArenaAllocator(.allocator = allocator)
    match initialized {
        ..ok ~constructed_value { arena = ~constructed_value }
        ..error _ {
            status_code = 1
            return
        }
    }
    allocated ::= allocate_bytes(.self = $&arena, .size = 8, .alignment = 3)
    match allocated {
        ..error _ { status_code = 2 }
        ..ok ~payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
    deinit(.self = $&arena)
}
