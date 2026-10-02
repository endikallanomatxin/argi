Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
compare(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := { result = left - right }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    callback ::= Comparator(.function = compare)
    moved := ~callback
    status_code = callback(7, 2)
}
