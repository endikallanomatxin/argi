main () -> (.status_code: Int32) := {
    value :: Int32 = 42
    ptr : &Int32 = &value
    _addr := ptr + 1
    status_code = 0
}
