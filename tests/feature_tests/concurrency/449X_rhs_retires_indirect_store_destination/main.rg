dispose := (.value: $&Allocation) -> (.result: UInt8) {
    deinit(value)
    result = 7
}
main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    handle ::= Virtual#(Allocator)($&allocator)
    owned ::= unwrap_or_abort(allocate#(UInt8)($&handle, .count = 1))
    pointer ::= trusted_establish_allocation_slot#(UInt8)(
        .allocation = &owned, .slot = owned.data, .anchor = owned.anchor
    )
    pointer& = dispose(.value = $&owned)
}
