Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
_absolute(.value: CInt) -> (.result: CInt) : CFunction(.symbol = "abs")
compare(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := { result = _absolute(.value = left) }
main(.system: System) -> () := {
    assume ffi := system.ffi
    callback := Comparator(.function = compare)
}
