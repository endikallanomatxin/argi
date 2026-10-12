main := (.system: System) -> (.status_code: Int32 = 0) {
    erased ::= to_virtual#(.contract: Allocator)(.value = system.page_allocator)
    allocation ::= unwrap_or_abort(allocate#(UInt32)($&erased, .count = 2))
    if allocation.size != 8 or allocation.alignment < 4 { abort }
    deinit($&allocation)
    single ::= unwrap_or_abort(allocate#(UInt32)($&erased))
    if single.size != 4 { abort }
    deinit($&single)
    empty ::= unwrap_or_abort(
        Allocator#(PageAllocator).allocate(system.page_allocator, .size = 0, .alignment = 1)
    )
    if empty.size != 0 { abort }
    deinit($&empty)
}
