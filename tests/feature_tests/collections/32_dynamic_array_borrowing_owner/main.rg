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
                            first ::= BorrowingOwner(.id = 1, .allocation = ~first_payload, .borrowed = external.data)
                            second ::= BorrowingOwner(.id = 2, .allocation = ~second_payload, .borrowed = external.data)
                            first_push ::= push#(.t: BorrowingOwner)(.self = $&array, .value = ~first)
                            second_push ::= push#(.t: BorrowingOwner)(.self = $&array, .value = ~second)
                            if is(.value = first_push, .variant = ..error) or is(.value = second_push, .variant = ..error) {
                                status_code = 4
                                return
                            }

                            popped ::= pop#(.t: BorrowingOwner)(.self = $&array)
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
