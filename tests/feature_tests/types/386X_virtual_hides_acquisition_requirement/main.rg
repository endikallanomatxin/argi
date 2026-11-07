Establish#(.T: Type): Contract = (
    .establish: (.self: &T, .storage: AcquiredStorage, .deallocator: Virtual#(Deallocator)) -> (.result: Allocation)
        where { owns(result) depends_on(result, deallocator) }
)
Provider := (.marker: UInt8)
implement Establish#(Provider) (
    .establish = (.self: &Provider, .storage: AcquiredStorage, .deallocator: Virtual#(Deallocator)) -> (.result: Allocation) {
        result = establish_allocation(.storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator)
    }
)
main := () -> () {
    provider ::= Provider(0)
    erased ::= Virtual#(Establish)(&provider)
}
