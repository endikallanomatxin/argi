_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
_wrapper(.value: Int32) -> (.result: Int32) := { result = _absolute(value) }
_forward(.value: Int32) -> (.result: Int32) := { result = _wrapper(value) }
_local(.context: $&ForeignFunctionInterface, .value: Int32) -> (.result: Int32) : CFunction := {
    assume ffi := context
    result = _absolute(value)
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    if _forward(-42) != 42 { status_code = 1 }
    if _absolute(.value = -7, .ffi = system.ffi) != 7 { status_code = 2 }
    if _local(.context = system.ffi, .value = -9) != 9 { status_code = 3 }
}
