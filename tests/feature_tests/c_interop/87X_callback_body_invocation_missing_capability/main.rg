Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
_nested(.callback: Comparator, .left: CInt, .right: CInt) -> (.result: CInt) : CFunction := {
    result = callback(.left = left, .right = right)
}
_nested_type(.callback: Comparator, .left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    selected := _nested_type(.function = _nested)
}
