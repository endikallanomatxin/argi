Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: AcquiredStorage) where owns(result)
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi))
    }
)
choose := (
    .ffi: $&ForeignFunctionInterface, .first: [1]AcquiredStorage, .flag: Bool
) -> (.result: [1]AcquiredStorage) {
    if flag {
        result = ~first
    } else {
        acquired ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = ffi))
        result = (~acquired)
    }
}
main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= Virtual#(Deallocator)($&allocator)
    provider ::= Provider(system.ffi)
    factory ::= Virtual#(Acquire)(&provider)
    acquired ::= Acquire#().acquire(&factory)
    first: [1]AcquiredStorage = (~acquired)
    selected ::= choose(.ffi = system.ffi, .first = ~first, .flag = true)
    value ::= ~selected[0]
    allocation ::= establish_allocation(.storage = ~value, .size = 8, .alignment = 8, .deallocator = deallocator)
}
