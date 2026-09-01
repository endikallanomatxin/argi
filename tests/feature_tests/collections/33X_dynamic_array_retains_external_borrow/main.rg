BorrowingOwner : Type = (.allocation: Allocation, .borrowed: $&UInt8)
deinit(.self: $&BorrowingOwner) -> () := { deinit(.self = $&self&.allocation) }

main(.system: System) -> (.status_code: Int32 = 0) := {
    external_result ::= allocate(.self = system.allocator, .size = 1)
    owned_result ::= allocate(.self = system.allocator, .size = 1)
    match external_result {
        ..error _ { status_code = 1 }
        ..ok ~ external_payload {
            external ::= ~external_payload
            match owned_result {
                ..error _ { status_code = 2 }
                ..ok ~ owned_payload {
                    array ::= DynamicArray#(.t: BorrowingOwner)(.capacity = 1)
                    value ::= BorrowingOwner(.allocation = ~owned_payload, .borrowed = external.data)
                    push_assume_capacity#(.t: BorrowingOwner)(.self = $&array, .value = ~value)
                    deinit(.self = $&external)
                }
            }
        }
    }
}
