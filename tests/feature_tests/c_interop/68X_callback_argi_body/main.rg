Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
compare(.left: CInt, .right: CInt) -> (.result: CInt) := { result = left }
main() -> () := { callback := Comparator(.function = compare) }
