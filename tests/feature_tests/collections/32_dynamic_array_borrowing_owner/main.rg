unsafe_allocation := #import("../../_support/unsafe_allocation")
BorrowingOwner : Type = (
    .id: Int32
    .allocation: Allocation
    .borrowed: $&UInt8
)

first_drops :: Int32 = 0
second_drops :: Int32 = 0

deinit(.self: $&BorrowingOwner) -> () := {
    if self&.id == 1 { first_drops = first_drops + 1 }
    if self&.id == 2 { second_drops = second_drops + 1 }
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.allocator

    external_result ::= allocate(.self = system.allocator, .size = 1)
    first_result ::= allocate(.self = system.allocator, .size = 1)
    second_result ::= allocate(.self = system.allocator, .size = 1)
    match external_result {
        ..error _ { status_code = 1 }
        ..ok ~ external_payload {
            external ::= ~external_payload
            match first_result {
                ..error _ { status_code = 2 }
                ..ok ~ first_payload {
                    match second_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ second_payload {
                            array ::= DynamicArray#(.t: BorrowingOwner)(.capacity = 1)
                            first ::= BorrowingOwner(.id = 1, .allocation = ~first_payload, .borrowed = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&external, .offset = 0).reference)
                            second ::= BorrowingOwner(.id = 2, .allocation = ~second_payload, .borrowed = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&external, .offset = 0).reference)
                            first_push ::= push#(.t: BorrowingOwner)(.self = $&array, .value = ~first)
                            second_push ::= push#(.t: BorrowingOwner)(.self = $&array, .value = ~second)
                            if is(.value = first_push, .variant = ..error) or is(.value = second_push, .variant = ..error) {
                                status_code = 4
                                return
                            }

                            popped_result ::= pop#(.t: BorrowingOwner)(.self = $&array).result
                            if is(.value = popped_result, .variant = ..error) {
                                status_code = 5
                                return
                            }
                            popped ::= ~popped_result..ok
                            observed ::= popped.borrowed&
                            if observed == 255 { status_code = 5 }
                            deinit#(.t: BorrowingOwner)(.self = $&array)
                            if first_drops != 1 or second_drops != 0 { status_code = 6 }
                            deinit(.self = $&popped)
                            if second_drops != 1 { status_code = 7 }
                        }
                    }
                }
            }
        }
    }
}
