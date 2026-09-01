Borrowing : Type = (
    .reference: $&UInt8
)

consume_into_storage(
    .storage: $&Allocation,
    .slot: $&Allocation,
    .owner: Allocation,
) -> () := {
    trusted_opaque_move_in#(.t: Allocation, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~owner,
    )
}

main(.system: System) -> (.status_code: Int32) := {
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = system.allocator)

    target_storage ::= malloc(.size = 1)
    target ::= establish_allocation(.storage = target_storage, .size = 1, .deallocator = deallocator)

    borrowing_slots_storage ::= malloc(.size = size_of(.type = Borrowing))
    borrowing_slots ::= establish_allocation(
        .storage = borrowing_slots_storage,
        .size = size_of(.type = Borrowing),
        .deallocator = deallocator,
    )
    borrowing_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = borrowing_slots.data).reference
    hidden :: Borrowing = (.reference = target.data)
    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
        .storage = $&borrowing_slots,
        .destination = borrowing_slot,
        .source = ~hidden,
    )

    owner_slots_storage ::= malloc(.size = size_of(.type = Allocation))
    owner_slots ::= establish_allocation(
        .storage = owner_slots_storage,
        .size = size_of(.type = Allocation),
        .deallocator = deallocator,
    )
    owner_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = owner_slots.data).reference
    consume_into_storage(
        .storage = $&owner_slots,
        .slot = owner_slot,
        .owner = ~target,
    )
    status_code = 0
}
