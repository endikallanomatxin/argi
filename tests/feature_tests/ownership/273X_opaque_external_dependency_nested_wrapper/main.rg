unsafe_allocation := import("../../_support/unsafe_allocation")
BorrowingOwner : Type = (.allocation: Allocation, .borrowed: $&UInt8)
deinit(.self: $&BorrowingOwner) -> () := { deinit(.self = $&self&.allocation) }

inner(.storage: $&Allocation, .slot: $&BorrowingOwner, .value: BorrowingOwner) -> () := {
    trusted_opaque_move_in#(.t: BorrowingOwner, .storage_type: Allocation)(.storage = storage, .destination = slot, .source = ~value)
}

outer(.storage: $&Allocation, .slot: $&BorrowingOwner, .value: BorrowingOwner) -> () := {
    inner(.storage = storage, .slot = slot, .value = ~value)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    external_result ::= allocate(.self = $&allocator_storage, .size = 1)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = BorrowingOwner))
    owned_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match external_result {
        ..error _ { status_code = 1 }
        ..ok ~ external_payload {
            external ::= ~external_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    match owned_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ owned_payload {
                            value ::= BorrowingOwner(.allocation = ~owned_payload, .borrowed = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&external, .offset = 0).reference)
                            slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: BorrowingOwner)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
                            outer(.storage = $&slots, .slot = slot, .value = ~value)
                            deinit(.self = $&external)
                        }
                    }
                }
            }
        }
    }
}
