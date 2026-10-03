main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    assume backing_allocator ::= $&allocator_storage

    arena :: ArenaAllocator
    initialized ::= ArenaAllocator(.allocator = $&allocator_storage, .block_size = 0)
    match initialized {
        ..ok ~constructed_value { arena = ~constructed_value }
        ..error _ {
        status_code = 1
        return
    }
    }

    result ::= allocate(.self = $&arena, .size = 0)
    match result {
        ..error _ {
            deinit(.self = $&arena)
            status_code = 2
        }
        ..ok ~ payload {
            child ::= ~payload
            if child.size != 0 {
                status_code = 3
                return
            }
            -- Internal padding does not authorize access beyond the request.
            deinit(.self = $&child)
            deinit(.self = $&arena)
            status_code = 0
        }
    }
}
