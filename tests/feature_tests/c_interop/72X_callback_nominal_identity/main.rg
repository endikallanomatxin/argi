Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
Other(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
_get() -> (.result: Other) : CFunction
_apply(.callback: Comparator) -> () : CFunction
main(.system: System) -> () := {
    assume ffi := system.ffi
    callback := _get()
    _apply(.callback = callback)
}
