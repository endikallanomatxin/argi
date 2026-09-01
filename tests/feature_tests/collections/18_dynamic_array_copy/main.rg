main(.system: System = System()) -> (.status_code: Int32) := {
    arr ::= DynamicArray#(.t: Int32)(.capacity = 1)
    #defer deinit(.self = $&arr, .allocator = system.allocator)

    push(.self = $&arr, .value = 10, .allocator = system.allocator)
    push(.self = $&arr, .value = 20, .allocator = system.allocator)

    copied_result ::= copy#(.t: Int32)(.self = &arr)
    if is(.value = copied_result, .variant = ..error) {
        status_code = 5
        return
    }
    copied ::= ~copied_result..ok
    #defer deinit(.self = $&copied, .allocator = system.allocator)

    copied[0] = 99
    push(.self = $&copied, .value = 30, .allocator = system.allocator)

    if arr.length != 2 {
        status_code = 1
        return
    }

    if copied.length != 3 {
        status_code = 2
        return
    }

    if arr[0] != 10 {
        status_code = 3
        return
    }

    if copied[0] != 99 {
        status_code = 4
        return
    }

    status_code = 0
}
