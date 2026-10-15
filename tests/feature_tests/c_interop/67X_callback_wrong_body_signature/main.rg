Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
compare(.left: CFloat, .right: CFloat) -> (.result: CFloat) : CFunction := { result = left }
main() -> () := { callback := Comparator(.function = compare) }
