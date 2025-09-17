-- Validate interaction between read-only and read/write pointers.

read_value(.ptr: &Int32) -> (.value: Int32) := {
    value = ptr&
}

increment(.ptr: $&Int32) -> () := {
    ptr& = ptr& + 1
}

main () -> (.status_code: Int32) := {
    x :: Int32 = 10

    ro : &Int32 = &x
    if read_value(.ptr=ro).value != 10 {
        status_code = 1
        return
    }

    rw : $&Int32 = $&x
    increment(.ptr=rw)

    if x != 11 {
        status_code = 2
        return
    }

    if read_value(.ptr=rw).value != 11 {
        status_code = 3
        return
    }

    status_code = 0
}
