Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
compare(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := { result = left - right }
main() -> (.status_code: Int32 = 0) := {
    callback := Comparator(.function = compare)
    status_code = callback(7, 2)
}
