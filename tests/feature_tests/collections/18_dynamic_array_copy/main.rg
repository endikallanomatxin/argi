main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator

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

    set_result ::= set(.self = $&copied, .index = 0, .value = 99, .allocator = system.allocator).result
    if is(.value = set_result, .variant = ..error) {
        status_code = 6
        return
    }
    push(.self = $&copied, .value = 30, .allocator = system.allocator)

    if length#(.t: Int32)(.self = &arr).count != 2 {
        status_code = 1
        return
    }

    if length#(.t: Int32)(.self = &copied).count != 3 {
        status_code = 2
        return
    }

    first_result ::= get(.self = &arr, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 3
        return
    }
    if first_result..ok != 10 {
        status_code = 3
        return
    }

    copied_first_result ::= get(.self = &copied, .index = 0).result
    if is(.value = copied_first_result, .variant = ..error) {
        status_code = 4
        return
    }
    if copied_first_result..ok != 99 {
        status_code = 4
        return
    }

    status_code = 0
}
