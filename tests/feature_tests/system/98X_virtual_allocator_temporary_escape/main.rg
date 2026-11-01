escape := (.system: System) -> (.result: Allocation) {
    assume allocator := GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    result = unwrap_or_abort(allocate#(UInt32)(allocator))
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocation ::= escape(system)
    deinit($&allocation)
}
