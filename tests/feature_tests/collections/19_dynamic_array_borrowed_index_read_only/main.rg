main(.system: System = System()) -> (.status_code: Int32) := {
    arr ::= DynamicArray#(.t: Int32)(.capacity = 2)
    #defer deinit(.self = $$&arr, .allocator = system.allocator)

    push(.self = $$&arr, .value = 10, .allocator = system.allocator)
    push(.self = $$&arr, .value = 20, .allocator = system.allocator)

    first :: Int32 = arr[0]
    second_ptr : &Int32 = &arr[1]

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
