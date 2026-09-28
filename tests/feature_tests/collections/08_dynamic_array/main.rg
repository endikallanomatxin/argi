main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    initial_capacity :: UIntNative = 2
    first_offset :: UIntNative = 0
    second_offset :: UIntNative = 1
    third_offset :: UIntNative = 2
    insert_offset :: UIntNative = 1

    arr :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = initial_capacity)
    #defer deinit(.self = $&arr)

    push(.self = $&arr, .value = 10)
    push(.self = $&arr, .value = 20)
    insert(.self = $&arr, .i = insert_offset, .value = 15)
    push(.self = $&arr, .value = 30)

    if length#(.t: Int32)(.self = &arr).count != 4 {
        status_code = 1
        return
    }

    if capacity#(.t: Int32)(.self = &arr).count < 4 {
        status_code = 2
        return
    }

    first_result ::= get(.self = &arr, .index = first_offset).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 3
        return
    }
    first ::= first_result..ok
    if first != 10 {
        status_code = 3
        return
    }

    second_before_result ::= get(.self = &arr, .index = second_offset).result
    if is(.value = second_before_result, .variant = ..error) {
        status_code = 4
        return
    }
    second_before ::= second_before_result..ok
    if second_before != 15 {
        status_code = 4
        return
    }

    set_result ::= set(.self = $&arr, .index = second_offset, .value = 99, .allocator = allocator).result
    if is(.value = set_result, .variant = ..error) {
        status_code = 5
        return
    }

    second_result ::= get(.self = &arr, .index = second_offset).result
    if is(.value = second_result, .variant = ..error) {
        status_code = 5
        return
    }
    second ::= second_result..ok
    if second != 99 {
        status_code = 5
        return
    }

    third_result ::= get(.self = &arr, .index = third_offset).result
    if is(.value = third_result, .variant = ..error) {
        status_code = 6
        return
    }
    third ::= third_result..ok
    if third != 20 {
        status_code = 6
        return
    }

    fourth_offset :: UIntNative = 3
    fourth_result ::= get(.self = &arr, .index = fourth_offset).result
    if is(.value = fourth_result, .variant = ..error) {
        status_code = 7
        return
    }
    fourth ::= fourth_result..ok
    if fourth != 30 {
        status_code = 7
        return
    }

    last_result ::= pop(.self = $&arr).result
    if is(.value = last_result, .variant = ..error) {
        status_code = 8
        return
    }
    last ::= last_result..ok
    if last != 30 {
        status_code = 8
        return
    }

    if length#(.t: Int32)(.self = &arr).count != 3 {
        status_code = 9
        return
    }

    status_code = 0
}
