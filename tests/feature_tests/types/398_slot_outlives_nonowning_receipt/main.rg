main := (.system: System) -> () {
    backing ::= CAllocator(.ffi = system.ffi)
    allocator ::= to_virtual#(Allocator)($&backing)
    arena ::= unwrap_or_abort(.value = ArenaAllocator(.allocator = allocator, .block_size = 64))
    child ::= unwrap_or_abort(.value = allocate_bytes(.self = $&arena, .size = 8, .alignment = 8))
    marker :: UInt8 = 0
    unrelated ::= erase_reference#(UInt8)(.base = &marker)

    slot ::= trusted_establish_allocation_slot#(UInt64)(
        .allocation = &child,
        .slot = raw_pointer#(UInt64)(.address = child.data.address),
        .anchor = unrelated
    )
    deinit(.self = $&child)
    slot& = 42
}
