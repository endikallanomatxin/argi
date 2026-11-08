choose := (
    .ffi: $&ForeignFunctionInterface,
    .first: Errable#(AcquiredStorage, (..out_of_memory)),
    .flag: Bool
) -> (.result: Errable#(AcquiredStorage, (..out_of_memory))) {
    if flag {
        result = ~first
    } else {
        result = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = ffi)
    }
}
main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= Virtual#(Deallocator)($&allocator)
    first ::= acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi)
    acquired ::= unwrap_or_abort(.value = choose(.ffi = system.ffi, .first = ~first, .flag = true))
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
}
