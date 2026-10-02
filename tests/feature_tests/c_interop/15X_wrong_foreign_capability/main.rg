_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
main() -> (.status_code: Int32 = 0) := {
    fake :: Int32 = 0
    assume ffi := $&fake
    status_code = _absolute(-1)
}
