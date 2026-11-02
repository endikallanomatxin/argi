main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    text ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 2))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 79))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 75))

    strings ::= unwrap_or_abort(.value = DynamicArray#(.t: String)(.capacity = 1))
    defer deinit(.self = $&strings)
    push(.self = $&strings, .value = ~text, .allocator = allocator)

    first_ptr_result ::= get_reference(.self = &strings, .index = 0).result
    if is(.value = first_ptr_result, .variant = ..error) {
        status_code = 1
        return
    }
    first_ptr: &String = first_ptr_result ..ok
    if unwrap_or_abort(.value = bytes_get(.view = first_ptr, .index = 0)) != 79 {
        status_code = 1
        return
    }

    mutable_ptr_result ::= get_mutable_reference(.self = $&strings, .index = 0).result
    if is(.value = mutable_ptr_result, .variant = ..error) {
        status_code = 2
        return
    }
    mutable_ptr: $&String = mutable_ptr_result ..ok
    _ ::= unwrap_or_abort(.value = set_ascii(.self = mutable_ptr, .index = 0, .byte = 78))

    final_ptr_result ::= get_reference(.self = &strings, .index = 0).result
    if is(.value = final_ptr_result, .variant = ..error) {
        status_code = 3
        return
    }
    if unwrap_or_abort(.value = bytes_get(.view = final_ptr_result ..ok, .index = 0)) != 78 {
        status_code = 2
        return
    }

    status_code = 0
}
