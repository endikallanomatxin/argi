main(.system: System, .condition: Bool = false) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
    ..error _ { status_code = 2 }
    ..ok ~ payload {
    allocation ::= ~payload

    if condition {
        deinit(.self = $&allocation)
    }

    if allocation.size == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
    }
    }
}
