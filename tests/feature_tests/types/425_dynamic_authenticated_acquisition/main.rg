select := (.values: $&[2]AcquiredStorage, .index: UIntNative) -> (.result: AcquiredStorage) {
    result = ~values&[index]
}
main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= Virtual#(Deallocator)($&allocator)
    first ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    second ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    values: [2]AcquiredStorage = (~first, ~second)
    selected ::= select(.values = $&values, .index = 1)
    allocation ::= establish_allocation(.storage = ~selected, .size = 8, .alignment = 8, .deallocator = deallocator)
}
