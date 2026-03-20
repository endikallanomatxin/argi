add_one (.i: Int32) -> (.o: Int32) := {
    o = i + 1
}

sum_pair (.a: Int32, .b: Int32) -> (.sum: Int32) := {
    sum = a + b
}

main () -> (.status_code: Int32) := {
    capacity :: UIntNative = 1
    middle :: UIntNative = 1

    arr ::= DynamicArray#(.t: Int32)(.capacity = capacity)
    #defer deinit(.self = $&arr)

    push(.self = $&arr, .value = 40)
    push(.self = $&arr, .value = 1 | add_one(.i = _))
    insert(.self = $&arr, .i = middle, .value = arr[0] | add_one(.i = _))

    popped ::= pop(.self = $&arr).value

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
