-- Negative test: passing a read-only pointer where a mutable pointer is required
increment(.ptr: $&Int32) -> () := {
    ptr& = ptr& + 1
}

main () -> (.status_code: Int32) := {
    value :: Int32 = 10
    reader : &Int32 = &value
    increment(.ptr=reader)
    status_code = 0
}
