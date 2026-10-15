main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    original ::= unwrap_or_abort(.value = String(.length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&original, .index = 0, .byte = 65))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&original, .index = 1, .byte = 114))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&original, .index = 2, .byte = 103))

    copied_result ::= copy(.self = &original, .allocator = allocator)
    match copied_result {
        ..error _ { status_code = 4 }
        ..ok ~copied_payload {
            copied ::= ~copied_payload
            _ ::= unwrap_or_abort(.value = set_ascii(.self = $&copied, .index = 0, .byte = 66))

            original_first ::= unwrap_or_abort(
                .value = bytes_get(.view = &original, .index = 0)
            )
            copied_first ::= unwrap_or_abort(.value = bytes_get(.view = &copied, .index = 0))
            copied_nul_rejected ::= is(
                .value = bytes_get(.view = &copied, .index = 3), .variant = ..error
            )

            if original_first != 65 {
                status_code = 1
                return
            }

            if copied_first != 66 {
                status_code = 2
                return
            }

            if copied_nul_rejected == false {
                status_code = 3
                return
            }

            status_code = 0
        }
    }
}
