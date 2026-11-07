slot_from := #(.T: Type) (.allocation: &Allocation, .anchor: &Any) -> (.slot: $&T) {
    slot = trusted_establish_allocation_slot#(T)(
        .allocation = allocation,
        .slot = raw_pointer#(T)(.address = allocation&.data.address),
        .anchor = anchor
    )
}
main := (.system: System) -> () {
    backing ::= CAllocator(.ffi = system.ffi)
    allocator ::= Virtual#(Allocator)($&backing)
    arena ::= unwrap_or_abort(.value = ArenaAllocator(.allocator = allocator, .block_size = 64))
    child ::= unwrap_or_abort(.value = allocate_bytes(.self = $&arena, .size = 8, .alignment = 8))
    marker :: UInt8 = 0
    unrelated ::= erase_reference#(UInt8)(.base = &marker)

    slot ::= slot_from#(UInt64)(.allocation = &child, .anchor = unrelated)
    deinit(.self = $&child)
    reset(.self = $&arena)
    slot& = 42
}
