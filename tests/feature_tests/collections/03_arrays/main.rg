-- Arrays constructed from list literals allocate storage and copy elements.
main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    arr :: [3]Int32 = (10, 20, 30)
    -- arr is now an array of three Int32 values: 10, 20, and 30.

    if length(.value = arr) != 3 {
        status_code = 1
        return
    }

    first :: Int32 = arr[0]
    if first != 10 {
        status_code = 2
        return
    }

    second :: Int32 = arr[1]
    if second != 20 {
        status_code = 3
        return
    }

    arr[1] = 99
    updated :: Int32 = arr[1]
    if updated != 99 {
        status_code = 4
        return
    }

    if length(.value = (10, 20, 30)) != 3 {
        status_code = 5
        return
    }

    values: Array#(.n = 3, .t: Int32) = (4, 5, 6)
    if length(.value = values) != 3 or values[1] != 5 {
        status_code = 6
        return
    }

    idx :: UIntNative = 1
    if arr[idx] != 99 {
        status_code = 7
        return
    }
    arr[idx] = 42
    if arr[idx] != 42 {
        status_code = 8
        return
    }

    status_code = 0
}
