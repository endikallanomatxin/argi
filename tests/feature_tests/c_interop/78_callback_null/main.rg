Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
_lookup(.present: CInt) -> (.result: Comparator) : CFunction(.symbol = "argi_callback_lookup")
_accept_null(.callback: Comparator) -> (.result: CInt) : CFunction(.symbol = "argi_callback_accept_null")

argi_callback_null() -> (.result: Comparator) : CFunction(.export = true) := {
    result = zeroed#(.t: Comparator)()
}

_same(.left: Comparator, .right: Comparator) -> (.result: Bool) := {
    result = left == right
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    absent := zeroed#(.t: Comparator)()
    missing := _lookup(.present = 0)
    present := _lookup(.present = 1)
    if missing != absent {
        status_code = 1
        return
    }
    if present == absent {
        status_code = 2
        return
    }
    if _accept_null(.callback = absent) != 1 {
        status_code = 3
        return
    }
    if _same(.left = missing, .right = absent) == false {
        status_code = 4
        return
    }
    callbacks := zeroed#(.t: [2]Comparator)()
    if callbacks[0] != absent { status_code = 5 }
}
