unsafe_allocation := #import("../../_support/unsafe_allocation")
BorrowingOwner : Type = (.allocation: Allocation, .borrowed: $&UInt8)
deinit(.self: $&BorrowingOwner) -> () := { deinit(.self = $&self&.allocation) }

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    external_result ::= allocate(.self = $&allocator_storage, .size = 1)
    owned_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match external_result {
        ..error _ { status_code = 1 }
        ..ok ~ external_payload {
            external ::= ~external_payload
            match owned_result {
                ..error _ { status_code = 2 }
                ..ok ~ owned_payload {
                    array ::= unwrap_or_abort(.value = DynamicArray#(.t: BorrowingOwner)(.capacity = 1))
                    value ::= BorrowingOwner(.allocation = ~owned_payload, .borrowed = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&external, .offset = 0).reference)
                    push_assume_capacity#(.t: BorrowingOwner)(.self = $&array, .value = ~value)
                    deinit(.self = $&external)
                }
            }
        }
    }
}
