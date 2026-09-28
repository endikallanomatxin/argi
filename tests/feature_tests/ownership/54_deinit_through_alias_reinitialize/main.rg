main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
    ..error _ { status_code = 2 }
    ..ok ~ payload {
    allocation ::= ~payload
    a ::= $&allocation
    b ::= $&allocation

    deinit(.self = a)

    replacement ::= allocate(.self = $&allocator_storage, .size = 1)
    match replacement {
    ..error _ { status_code = 3 }
    ..ok ~ replacement_payload {
    b& = ~replacement_payload
    if b&.size == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
    }
    }
    }
    }
}
