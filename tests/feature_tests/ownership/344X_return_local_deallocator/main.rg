escape(.ffi: $&ForeignFunctionInterface) -> (.result: Allocation) := {
    allocator ::= CAllocator(ffi)
    result = unwrap_or_abort(allocate($&allocator, .size = 8, .alignment = 1))
}

main(.system: System) -> () := {
    allocation ::= escape(system.ffi)
}
