main := (.system: System) -> () {
    provider ::= CAllocator(.ffi = system.ffi)
    first ::= unwrap_or_abort(.value = allocate_bytes(.self = $&provider, .size = 8, .alignment = 8))
    second ::= unwrap_or_abort(.value = allocate_bytes(.self = $&provider, .size = 8, .alignment = 8))
    -- A valid address from another allocation is not a subrange of first.
    first.data = second.data
    slot ::= trusted_establish_allocation_slot#(.t: UInt64)(
        .allocation = &first,
        .slot = raw_pointer#(.t: UInt64)(.address = first.data.address),
        .anchor = first.anchor
    )
    slot& = 42
}
