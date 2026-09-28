main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text ::= String(.allocator = $&allocator_storage, .length = 2)
    bytes_set(.string = $&text, .index = 0, .value = 79)
    bytes_set(.string = $&text, .index = 1, .value = 75)

    strings ::= DynamicArray#(.t: String)(.capacity = 1)
    #defer deinit(.self = $&strings, .allocator = $&allocator_storage)
    push(.self = $&strings, .value = ~text, .allocator = $&allocator_storage)

    first_ptr_result ::= get_ro_ref(.self = &strings, .index = 0).result
    if is(.value = first_ptr_result, .variant = ..error) {
        status_code = 1
        return
    }
    first_ptr : &String = first_ptr_result..ok
    if bytes_get(.string = first_ptr, .index = 0).byte != 79 {
        status_code = 1
        return
    }

    mutable_ptr_result ::= get_rw_ref(.self = $&strings, .index = 0).result
    if is(.value = mutable_ptr_result, .variant = ..error) {
        status_code = 2
        return
    }
    mutable_ptr : $&String = mutable_ptr_result..ok
    bytes_set(.string = mutable_ptr, .index = 0, .value = 78)

    final_ptr_result ::= get_ro_ref(.self = &strings, .index = 0).result
    if is(.value = final_ptr_result, .variant = ..error) {
        status_code = 3
        return
    }
    if bytes_get(.string = final_ptr_result..ok, .index = 0).byte != 78 {
        status_code = 2
        return
    }

    status_code = 0
}
