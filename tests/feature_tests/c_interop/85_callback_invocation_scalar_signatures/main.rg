Narrow(.value: CSignedChar) -> (.result: CShort) : CFunctionPointer
Floating(.left: CDouble, .right: CFloat) -> (.result: CDouble) : CFunctionPointer
Notify(.value: CInt) -> () : CFunctionPointer
_get_narrow() -> (.result: Narrow) : CFunction(.symbol = "argi_get_narrow")
_get_floating() -> (.result: Floating) : CFunction(.symbol = "argi_get_floating")
_get_notify() -> (.result: Notify) : CFunction(.symbol = "argi_get_notify")
_notified() -> (.result: CInt) : CFunction(.symbol = "argi_notified")

Values : CStruct = (.left: CDouble, .right: CFloat, .expected: CDouble)
_get_values() -> (.result: Values) : CFunction(.symbol = "argi_get_values")

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    narrow := _get_narrow()
    floating := _get_floating()
    notify := _get_notify()
    if narrow(.value = -7) != -14 { status_code = 1 }
    values := _get_values()
    if floating(.left = values.left, .right = values.right) != values.expected { status_code = 2 }
    if floating(.left = 2.5, .right = 1.25) != values.expected { status_code = 4 }
    notify(.value = 19)
    if _notified() != 19 { status_code = 3 }
}
