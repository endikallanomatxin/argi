main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator

    arr ::= DynamicArray#(.t: Int32)(.capacity = 2)
    #defer deinit(.self = $&arr, .allocator = system.allocator)

    push(.self = $&arr, .value = 10, .allocator = system.allocator)
    push(.self = $&arr, .value = 20, .allocator = system.allocator)

    first_result ::= get(.self = &arr, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 1
        return
    }
    first ::= first_result..ok
    second_ptr_result ::= get_ro_ref(.self = &arr, .index = 1).result
    if is(.value = second_ptr_result, .variant = ..error) {
        status_code = 2
        return
    }
    second_ptr : &Int32 = second_ptr_result..ok

    if first != 10 {
        status_code = 1
        return
    }

    if second_ptr& != 20 {
        status_code = 2
        return
    }

    status_code = 0
}
