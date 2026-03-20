main () -> (.status_code: Int32) := {
    arr :: DynamicArray#(.t: Int32)
    initial_capacity :: UIntNative = 2
    first_offset :: UIntNative = 0
    second_offset :: UIntNative = 1
    third_offset :: UIntNative = 2

    dynamic_array_init#(.t: Int32)(.array = $&arr, .capacity = initial_capacity)
    #defer dynamic_array_deinit#(.t: Int32)(.array = $&arr)

    dynamic_array_push#(.t: Int32)(.array = $&arr, .value = 10)
    dynamic_array_push#(.t: Int32)(.array = $&arr, .value = 20)
    dynamic_array_push#(.t: Int32)(.array = $&arr, .value = 30)

    if arr.length != 3 {
        status_code = 1
        return
    }

    if arr.capacity < 3 {
        status_code = 2
        return
    }

    first :: Int32 = arr[first_offset]
    if first != 10 {
        status_code = 3
        return
    }

    arr[second_offset] = 99

    second :: Int32 = arr[second_offset]
    if second != 99 {
        status_code = 4
        return
    }

    third :: Int32 = arr[third_offset]
    if third != 30 {
        status_code = 5
        return
    }

    status_code = 0
}
