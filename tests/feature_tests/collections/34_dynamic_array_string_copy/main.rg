main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    array ::= unwrap_or_abort(.value = DynamicArray#(.t: String)(.capacity = 1))
    defer deinit(.self = $&array)
    text ::= unwrap_or_abort(.value = String(.length = 1))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 65))
    pushed ::= push(.self = $&array, .value = ~text)
    if is(.value = pushed, .variant = ..error) {
        status_code = 1
        return
    }

    copied_result ::= copy(.self = &array, .allocator = $&allocator_storage)
    match copied_result {
        ..error _ { status_code = 2 }
        ..ok ~copied_payload {
            copied ::= ~copied_payload
            defer deinit(.self = $&copied)
            original ::= dynamic_array_element_reference#(.t: String)(
                .array = &array, .offset = 0
            ).pointer
            duplicate ::= dynamic_array_element_mutable_reference#(.t: String)(
                .array = $&copied, .offset = 0
            ).pointer
            _ ::= unwrap_or_abort(.value = set_ascii(.self = duplicate, .index = 0, .byte = 66))
            if unwrap_or_abort(.value = bytes_get(.view = original, .index = 0)) != 65 {
                status_code = 3
                return
            }
            if unwrap_or_abort(.value = bytes_get(.view = duplicate, .index = 0)) != 66 {
                status_code = 4
            }
        }
    }
}
