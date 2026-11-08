Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: AcquiredStorage) where owns(result)
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi))
    }
)
select := (.values: $&[2]AcquiredStorage, .index: UIntNative) -> (.result: AcquiredStorage) {
    result = ~values&[index]
}
main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= Virtual#(Deallocator)($&allocator)
    provider ::= Provider(system.ffi)
    factory ::= Virtual#(Acquire)(&provider)
    first ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    second ::= Acquire#().acquire(&factory)
    values: [2]AcquiredStorage = (~first, ~second)
    selected ::= select(.values = $&values, .index = 1)
    allocation ::= establish_allocation(.storage = ~selected, .size = 8, .alignment = 8, .deallocator = deallocator)
}
