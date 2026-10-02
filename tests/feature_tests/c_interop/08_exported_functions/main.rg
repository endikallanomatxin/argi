helper(.left: Int32, .right: Int32) -> (.result: Int32) := {
    result = left + right
}

_sum(.left: Int32, .right: Int32) -> (.result: Int32)
    : CFunction(.export = true, .symbol = "argi_export_sum") := {
    result = helper(left, right)
}

argi_export_set(.value: $&Int32) -> () : CFunction(.export = true) := {
    value& = 42
    return
}

_local(.value: Int32) -> (.result: Int32) : CFunction := {
    result = value + 1
    return
}

argi_export_float(.left: Float64, .right: Float64) -> (.result: Float64)
    : CFunction(.export = true) := {
    result = left + right
}

argi_c_probe() -> (.result: Int32) : CFunction

main() -> (.status_code: Int32 = 0) := {
    if argi_c_probe() != 0 { status_code = 1 }
    if _local(6) != 7 { status_code = 2 }
}
