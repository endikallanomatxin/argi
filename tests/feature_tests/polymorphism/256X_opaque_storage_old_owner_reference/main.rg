unsafe_allocation := import ("../../_support/unsafe_allocation")

Store: Abstract = (
    put(.self: &Self, .storage: $&Allocation, .slot: $&Allocation, .value: Allocation) -> () where retains(
        storage
        value
    )
)

Cell: Type = ()

Cell implements Store

put(.self: &Cell, .storage: $&Allocation, .slot: $&Allocation, .value: Allocation) -> () := {
    trusted_opaque_move_in#(Allocation, Allocation)(storage, slot, ~value)
}

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    storage ::= unwrap_or_abort(allocate#(Allocation)(allocator))
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Allocation)(
        unsafe_allocation.trusted_allocation_byte_rw($&storage, 0).reference
    ).reference
    value ::= unwrap_or_abort(allocate(allocator, .size = 1))
    previous ::= unsafe_allocation.trusted_allocation_byte_ro(&value, 0).reference
    cell ::= Cell()
    erased ::= to_virtual#(Store)(&cell)

    put(&erased, $&storage, slot, ~value)
    if previous&== 0 { abort }
}
