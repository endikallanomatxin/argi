Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: AcquiredStorage) where owns(result)
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi))
    }
)
choose := (.flag: Bool, .first: AcquiredStorage, .second: AcquiredStorage) -> (.result: AcquiredStorage) {
    selected :: AcquiredStorage
    if flag { selected = ~second } else { selected = ~first }
    result = ~selected
}
main := (.system: System) -> () {
    provider ::= Provider(system.ffi)
    factory ::= Virtual#(Acquire)(&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= Virtual#(Deallocator)($&allocator)
    first ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    second ::= Acquire#().acquire(&factory)
    acquired ::= choose(.flag = false, .first = ~first, .second = ~second)
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
}
