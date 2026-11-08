Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: Errable#(AcquiredStorage, (..out_of_memory))) where {
        on result ..ok { owns(result) }
        on result ..error {}
    }
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: Errable#(AcquiredStorage, (..out_of_memory))) {
        result = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi)
    }
)
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
    provider ::= Provider(system.ffi)
    factory ::= Virtual#(Acquire)(&provider)
    first ::= Acquire#().acquire(&factory)
    acquired ::= unwrap_or_abort(.value = choose(.ffi = system.ffi, .first = ~first, .flag = true))
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
}
