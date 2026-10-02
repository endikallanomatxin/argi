_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
main() -> (.status_code: Int32 = 0) := { status_code = _absolute(-1) }
