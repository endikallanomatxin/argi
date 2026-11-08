Borrow := #(.T: Type) (.value: $&T)
borrow := #(.T: Type) (.allocation: &Allocation) -> (.result: Borrow#(T)) {
    pointer ::= trusted_establish_allocation_slot#(.t: T)(
        .allocation = allocation,
        .slot = raw_pointer#(.t: T)(.address = allocation&.data.address),
        .anchor = allocation&.anchor
    )
    result = (.value = pointer)
}
main := (.system: System) -> () {
    provider ::= CAllocator(.ffi = system.ffi)
    allocation ::= unwrap_or_abort(.value = allocate_bytes(.self = $&provider, .size = 8, .alignment = 8))
    borrowed ::= borrow#(.T: UInt64)(.allocation = &allocation)
    deinit(.self = $&allocation)
    borrowed.value& = 42
}
