main := (.system: System) -> (.status_code: Int32) {

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

    left_view ::= view(.self = &left)
    combined_result ::= &left_view + "\n"
    match combined_result {
        ..error _ { status_code = 2 }
        ..ok ~combined {

            combined_view ::= view(.self = &combined)

            if combined_view == "hello\n" {
                status_code = 0
            } else {
                status_code = 1
            }
        }
    }
}
