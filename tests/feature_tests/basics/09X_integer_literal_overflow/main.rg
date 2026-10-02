main () -> (.status_code: Int32) := {
    value : UInt8 = 300
    status_code = 0
    if value != 0 { status_code = 1 }
}
