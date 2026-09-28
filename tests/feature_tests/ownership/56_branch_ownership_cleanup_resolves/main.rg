main(.system: System, .condition: Bool = false) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    owner ::= ~payload

    if condition {
        moved ::= ~owner
        if moved.size == 1 {
            status_code = 0
        }
    }

    status_code = 0
    }
    }
}
