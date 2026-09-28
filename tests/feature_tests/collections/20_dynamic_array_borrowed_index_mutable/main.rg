main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    arr ::= DynamicArray#(.t: Int32)(.capacity = 2)
    #defer deinit(.self = $&arr, .allocator = $&allocator_storage)

    push(.self = $&arr, .value = 10, .allocator = $&allocator_storage)
    push(.self = $&arr, .value = 20, .allocator = $&allocator_storage)

    first_ptr_result ::= get_rw_ref(.self = $&arr, .index = 0).result
    if is(.value = first_ptr_result, .variant = ..error) {
        status_code = 1
        return
    }
    first_ptr : $&Int32 = first_ptr_result..ok
    first_ptr& = 99

    first_result ::= get(.self = &arr, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 2
        return
    }
    if first_result..ok != 99 {
        status_code = 1
        return
    }

    second_ptr_result ::= get_rw_ref(.self = $&arr, .index = 1).result
    if is(.value = second_ptr_result, .variant = ..error) {
        status_code = 3
        return
    }
    second_ptr : $&Int32 = second_ptr_result..ok
    second_ptr& = 77

    second_result ::= get(.self = &arr, .index = 1).result
    if is(.value = second_result, .variant = ..error) {
        status_code = 4
        return
    }
    if second_result..ok != 77 {
        status_code = 2
        return
    }

    status_code = 0
}
