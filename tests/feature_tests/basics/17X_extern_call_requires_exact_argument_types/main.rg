main(.system: System) -> (.status_code: Int32) := {
    assume ffi := system.ffi
    value :: UInt16 = 10
    putchar(.character = value)
    status_code = 0
}
