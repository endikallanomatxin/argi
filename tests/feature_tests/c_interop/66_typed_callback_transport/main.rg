types := import("./dep")

_lookup() -> (.result: types.Comparator) : CFunction(.symbol = "argi_callback_lookup")
_apply(.callback: types.Comparator, .left: CInt, .right: CInt) -> (.result: CInt)
    : CFunction(.symbol = "argi_callback_apply")
_entry(.callback: types.Comparator) -> (.result: types.Entry)
    : CFunction(.symbol = "argi_callback_entry")
_apply_entry(.entry: types.Entry) -> (.result: CInt)
    : CFunction(.symbol = "argi_callback_apply_entry")

argi_callback_echo(.callback: types.Comparator) -> (.result: types.Comparator)
    : CFunction(.export = true) := { result = callback }

_difference(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := {
    result = left - right
}

_difference(.left: CFloat, .right: CFloat) -> (.result: CFloat) : CFunction := {
    result = left + right
}

_invoke(.callback: types.Comparator) -> (.result: CInt) := {
    result = callback(.left = 21, .right = 4)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    selected := types.Comparator(.function = _difference)
    if _apply(.callback = selected, .left = 20, .right = 3) != 17 {
        status_code = 5
        return
    }
    imported := types.Comparator(.function = types.difference)
    if _apply(.callback = imported, .left = 9, .right = 2) != 7 {
        status_code = 6
        return
    }
    callback := _lookup()
    if callback(.left = 8, .right = 3) != 5 {
        status_code = 7
        return
    }
    if selected(11, 4) != 7 {
        status_code = 8
        return
    }
    if _invoke(.callback = callback) != 17 {
        status_code = 9
        return
    }
    copied := callback
    if _apply(.callback = copied, .left = 7, .right = 3) != 4 {
        status_code = 1
        return
    }
    entry := _entry(.callback = callback)
    if entry.callback(.left = 10, .right = 3) != 7 {
        status_code = 10
        return
    }
    if _apply_entry(.entry = entry) != 21 {
        status_code = 2
        return
    }
    if _apply(.callback = entry.callback, .left = 42, .right = 2) != 40 {
        status_code = 3
        return
    }
    if size_of(.type = type_of(.value = callback)) != size_of(.type = UIntNative) {
        status_code = 4
    }
}
