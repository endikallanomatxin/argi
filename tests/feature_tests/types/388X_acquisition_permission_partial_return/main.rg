Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: AcquiredStorage) where owns(result)
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi))
    }
)
choose := (.system: System, .flag: Bool, .factory: Virtual#(Acquire)) -> (.result: AcquiredStorage) {
    if flag {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    } else {
        result = Acquire#().acquire(&factory)
    }
}
main := (.system: System) -> () {
    provider ::= Provider(system.ffi)
    factory ::= Virtual#(Acquire)(&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= Virtual#(Deallocator)($&allocator)
    acquired ::= choose(.system = system, .flag = false, .factory = factory)
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
}
