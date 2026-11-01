main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := $&virtual_allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 1))
    first_push ::= push(.self = $&array, .value = 10, .allocator = allocator)
    if is(.value = first_push, .variant = ..error) {
        status_code = 1
        return
    }

    old_alias_result ::= get_reference(.self = &array, .index = 0).result
    if is(.value = old_alias_result, .variant = ..error) {
        status_code = 3
        return
    }
    old_alias ::= old_alias_result ..ok
    second_push ::= push(.self = $&array, .value = 20, .allocator = allocator)
    if is(.value = second_push, .variant = ..error) {
        status_code = 2
        return
    }

    status_code = old_alias&
    deinit(.self = $&array)
}
