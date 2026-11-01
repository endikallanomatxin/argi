main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := $&virtual_allocator

    line :: String = unwrap_or_abort(
        .value = String(.allocator = allocator, .length = 5)
    )
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&line, .index = 0, .byte = 104))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&line, .index = 1, .byte = 101))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&line, .index = 2, .byte = 108))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&line, .index = 3, .byte = 108))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&line, .index = 4, .byte = 111))

    combined_result ::= &line + "\n"
    match combined_result {
        ..error _ { status_code = 2 }
        ..ok ~with_newline {

            with_newline_view ::= view(.self = &with_newline)

            if with_newline_view == "hello\n" {
                status_code = 0
            } else {
                status_code = 1
            }
        }
    }
}
