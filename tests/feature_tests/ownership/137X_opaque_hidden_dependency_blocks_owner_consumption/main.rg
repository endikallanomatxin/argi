unsafe_allocation := import("../../_support/unsafe_allocation")
Borrowing : Type = (
    .reference: $&UInt8
)

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = $&allocator_storage)

    target_storage ::= malloc(.size = 1, .ffi = system.ffi)
    target ::= trusted_establish_allocation(.storage = target_storage, .size = 1, .alignment = 1, .deallocator = deallocator)

    borrowing_slots_storage ::= malloc(.size = size_of(.type = Borrowing), .ffi = system.ffi)
    borrowing_slots ::= trusted_establish_allocation(
        .storage = borrowing_slots_storage,
        .size = size_of(.type = Borrowing),
        .alignment = 1,
        .deallocator = deallocator,
    )
    borrowing_slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&borrowing_slots, .offset = 0).reference).reference
    hidden :: Borrowing = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
        .storage = $&borrowing_slots,
        .destination = borrowing_slot,
        .source = ~hidden,
    )

    owner_slots_storage ::= malloc(.size = size_of(.type = Allocation), .ffi = system.ffi)
    owner_slots ::= trusted_establish_allocation(
        .storage = owner_slots_storage,
        .size = size_of(.type = Allocation),
        .alignment = 1,
        .deallocator = deallocator,
    )
    owner_slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&owner_slots, .offset = 0).reference).reference

    -- Consuming `target` must not end its root while another opaque storage
    -- still hides the dependency carried by `unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference`.
    trusted_opaque_move_in#(.t: Allocation, .storage_type: Allocation)(
        .storage = $&owner_slots,
        .destination = owner_slot,
        .source = ~target,
    )
    status_code = 0
}
