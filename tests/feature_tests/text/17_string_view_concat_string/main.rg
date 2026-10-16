main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    left :: String = unwrap_or_abort(
        .value = String(.allocator = $&allocator_storage, .length = 5)
    )
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&left, .index = 0, .byte = 104))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&left, .index = 1, .byte = 101))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&left, .index = 2, .byte = 108))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&left, .index = 3, .byte = 108))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&left, .index = 4, .byte = 111))

    right :: String = unwrap_or_abort(
        .value = String(.allocator = $&allocator_storage, .length = 6)
    )
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&right, .index = 0, .byte = 32))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&right, .index = 1, .byte = 119))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&right, .index = 2, .byte = 111))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&right, .index = 3, .byte = 114))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&right, .index = 4, .byte = 108))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&right, .index = 5, .byte = 100))

    left_view ::= view(.self = &left)
    combined_result ::= &left_view + &right
    match combined_result {
        ..error _ { status_code = 2 }
        ..ok ~combined {

            combined_view ::= view(.self = &combined)

            if combined_view == "hello world" {
                status_code = 0
            } else {
                status_code = 1
            }
        }
    }
}
