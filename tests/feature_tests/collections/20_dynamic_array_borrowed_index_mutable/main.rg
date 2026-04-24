main(.system: System = System()) -> (.status_code: Int32) := {
    arr ::= DynamicArray#(.t: Int32)(.capacity = 2)
    #defer deinit(.self = $&arr, .allocator = system.allocator)

    push(.self = $&arr, .value = 10, .allocator = system.allocator)
    push(.self = $&arr, .value = 20, .allocator = system.allocator)

    first_ptr : $&Int32 = $&arr[0]
    first_ptr& = 99

    if arr[0] != 99 {
        status_code = 1
        return
    }

    second_ptr : $&Int32 = $&arr[1]
    second_ptr& = 77

    if arr[1] != 77 {
        status_code = 2
        return
    }

    status_code = 0
}
