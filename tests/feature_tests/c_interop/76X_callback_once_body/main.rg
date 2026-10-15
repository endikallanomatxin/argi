Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
once compare(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := { result = left }
main() -> () := { callback := Comparator(.function = compare) }
