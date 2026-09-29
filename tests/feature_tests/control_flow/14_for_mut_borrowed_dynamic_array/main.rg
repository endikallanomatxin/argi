main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    dyn ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 2))
    #defer deinit(.self = $&dyn, .allocator = $&allocator_storage)
    push(.self = $&dyn, .value = 7, .allocator = $&allocator_storage)
    push(.self = $&dyn, .value = 8, .allocator = $&allocator_storage)

    for $& value in dyn {
        value& = value& + 10
    }

    first_result ::= get(.self = &dyn, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 3
        return
    }
    if first_result..ok != 17 {
        status_code = 1
        return
    }

    second_result ::= get(.self = &dyn, .index = 1).result
    if is(.value = second_result, .variant = ..error) {
        status_code = 4
        return
    }
    if second_result..ok != 18 {
        status_code = 2
        return
    }

    status_code = 0
}
