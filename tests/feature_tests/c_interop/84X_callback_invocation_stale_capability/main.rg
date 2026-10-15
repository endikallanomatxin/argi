Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
compare(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := { result = left - right }
main() -> (.status_code: Int32 = 0) := {
    storage ::= ForeignFunctionInterface()
    assume ffi := $&storage
    callback := Comparator(.function = compare)
    moved := ~storage
    status_code = callback(7, 2)
}
