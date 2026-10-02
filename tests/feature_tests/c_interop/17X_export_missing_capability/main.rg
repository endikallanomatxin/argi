_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
_export(.value: Int32) -> (.result: Int32) : CFunction(.export = true, .symbol = "argi_unprivileged_export") := {
    result = _absolute(value)
}
main() -> (.status_code: Int32 = 0) := {}
