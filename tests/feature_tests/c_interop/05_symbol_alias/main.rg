_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
_other_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    first := _absolute(-42)
    second := _other_absolute(-7)
    if first != 42 { status_code = 1 }
    if second != 7 { status_code = 2 }
}
