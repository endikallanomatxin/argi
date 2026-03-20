sum_pair (.a: Int32, .b: Int32) -> (.sum: Int32) := {
    sum = a + b
}

main () -> (.status_code: Int32) := {
    capacity :: UIntNative = 1
    middle :: UIntNative = 1

    arr ::= DynamicArray#(.t: Int32)(.capacity = capacity)
    #defer deinit(.self = $&arr)

    arr | push(.self = $&_, .value = 40)
    arr | push(.self = $&_, .value = 2)
    arr | insert(.self = $&_, .i = middle, .value = arr[0])

    popped ::= arr | pop(.self = $&_) | _.value

    if popped != 2 {
        status_code = 1
        return
    }

    if arr.length != 2 {
        status_code = 2
        return
    }

    status_code = arr[0] | sum_pair(.a = _, .b = arr[1])
}
