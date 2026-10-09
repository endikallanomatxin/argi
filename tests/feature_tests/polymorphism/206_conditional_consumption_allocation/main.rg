release_if(.allocation: $&Allocation, .consume: Bool) -> (.result: ?Int32) := {
    if consume {
        deinit(allocation)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    allocation ::= unwrap_or_abort(allocate(.self = allocator, .size = 1))
    result ::= release_if($&allocation, false)

    match result {
        ..none { if allocation.size != 1 { status_code = 1 } }
        ..some _ { status_code = 2 }
    }
}
