sum_pair (.a: Int32, .b: Int32) -> (.sum: Int32) := {
    sum = a + b
}

main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    arr ::= DynamicArray#(.t: Int32)(.capacity = 1)
    #defer deinit(.self = $&arr)

    arr | push(.self = $&_, .value = 40)
    arr | push(.self = $&_, .value = 2)
    first_result ::= get(.self = &arr, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 3
        return
    }
    inserted ::= arr | insert(.self = $&_, .i = 1, .value = first_result..ok)
    if is(.value = inserted, .variant = ..error) {
        status_code = 4
        return
    }

    popped_result ::= arr | pop(.self = $&_) | _.result
    if is(.value = popped_result, .variant = ..error) {
        status_code = 5
        return
    }
    popped ::= popped_result..ok

    if popped != 2 {
        status_code = 1
        return
    }

    if length#(.t: Int32)(.self = &arr).count != 2 {
        status_code = 2
        return
    }

    first_after_pop ::= get(.self = &arr, .index = 0).result
    second_after_pop ::= get(.self = &arr, .index = 1).result
    if is(.value = first_after_pop, .variant = ..error) {
        status_code = 6
        return
    }
    if is(.value = second_after_pop, .variant = ..error) {
        status_code = 6
        return
    }
    status_code = first_after_pop..ok | sum_pair(.a = _, .b = second_after_pop..ok)
}
