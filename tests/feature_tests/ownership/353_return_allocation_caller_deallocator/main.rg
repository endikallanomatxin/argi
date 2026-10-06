make(.allocator: $&Allocator) -> (.result: Allocation) := {
    result = unwrap_or_abort(allocate(allocator, .size = 8, .alignment = 1))
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator ::= CAllocator(system.ffi)
    allocation ::= make($&allocator)

    if allocation.size != 8 { status_code = 1 }
}
