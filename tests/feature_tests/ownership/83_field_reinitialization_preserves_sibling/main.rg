Pair : Type = (
    .left: Allocation
    .right: Allocation
)

initialize_left(.p: $&Allocation, .value: Allocation) -> () := {
    p& = ~value
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    left_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match left_result {
        ..error _ { status_code = 1 }
        ..ok ~ left_payload {
            right_result ::= allocate(.self = $&allocator_storage, .size = 2)
            match right_result {
                ..error _ { status_code = 2 }
                ..ok ~ right_payload {
                    pair :: Pair = (.left = ~left_payload, .right = ~right_payload)
                    sibling ::= &pair.right
                    deinit(.self = $&pair.left)

                    replacement_result ::= allocate(.self = $&allocator_storage, .size = 3)
                    match replacement_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ replacement_payload {
                            initialize_left(.p = $&pair.left, .value = ~replacement_payload)
                            if sibling&.size == 2 {
                                status_code = 0
                            } else {
                                status_code = 4
                            }
                            deinit(.self = $&pair.left)
                            deinit(.self = $&pair.right)
                        }
                    }
                }
            }
        }
    }
}
