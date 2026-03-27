main () -> (.status_code: Int32) := {
    arr :: [3]Int32 = (10, 20, 30)
    idx :: UIntNative = 1

    if arr[idx] != 20 {
        status_code = 1
        return
    }

    arr[idx] = 99
    if arr[idx] != 99 {
        status_code = 2
        return
    }

    status_code = 0
}
