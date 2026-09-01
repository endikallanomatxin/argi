Borrowing : Type = (
    .reference: &UInt8
)

external :: UInt8 = 9

main(.system: System) -> (.status_code: Int32) := {
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = system.allocator)

    borrowing_slots_storage ::= malloc(.size = size_of(.type = Borrowing))
    borrowing_slots ::= establish_allocation(
        .storage = borrowing_slots_storage,
        .size = size_of(.type = Borrowing),
        .deallocator = deallocator,
    )
    borrowing_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = borrowing_slots.data).reference
    hidden :: Borrowing = (.reference = &external)
    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
        .storage = $&borrowing_slots,
        .destination = borrowing_slot,
        .source = ~hidden,
    )

    unrelated_storage ::= malloc(.size = 1)
    unrelated ::= establish_allocation(.storage = unrelated_storage, .size = 1, .deallocator = deallocator)
    owner_slots_storage ::= malloc(.size = size_of(.type = Allocation))
    owner_slots ::= establish_allocation(
        .storage = owner_slots_storage,
        .size = size_of(.type = Allocation),
        .deallocator = deallocator,
    )
    owner_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = owner_slots.data).reference
    trusted_opaque_move_in#(.t: Allocation, .storage_type: Allocation)(
        .storage = $&owner_slots,
        .destination = owner_slot,
        .source = ~unrelated,
    )

    trusted_opaque_drop(.slot = owner_slot)
    trusted_opaque_drop(.slot = borrowing_slot)
    deinit(.self = $&owner_slots)
    deinit(.self = $&borrowing_slots)
    status_code = 0
}
