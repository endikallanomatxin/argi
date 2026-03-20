main () -> (.status_code: Int32) := {
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

    if arr.length != 4 {
        status_code = 1
        return
    }

    if arr.capacity < 4 {
        status_code = 2
        return
    }

    first :: Int32 = arr[first_offset]
    if first != 10 {
        status_code = 3
        return
    }

    second_before :: Int32 = arr[second_offset]
    if second_before != 15 {
        status_code = 4
        return
    }

    arr[second_offset] = 99

    second :: Int32 = arr[second_offset]
    if second != 99 {
        status_code = 5
        return
    }

    third :: Int32 = arr[third_offset]
    if third != 20 {
        status_code = 6
        return
    }

    fourth_offset :: UIntNative = 3
    fourth :: Int32 = arr[fourth_offset]
    if fourth != 30 {
        status_code = 7
        return
    }

    last :: Int32 = pop(.self = $&arr).value
    if last != 30 {
        status_code = 8
        return
    }

    if arr.length != 3 {
        status_code = 9
        return
    }

    status_code = 0
}
