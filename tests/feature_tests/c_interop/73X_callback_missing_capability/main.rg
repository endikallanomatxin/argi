Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
compare(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := { result = left }
_apply(.callback: Comparator) -> () : CFunction
main() -> () := {
    callback := Comparator(.function = compare)
    _apply(.callback = callback)
}
