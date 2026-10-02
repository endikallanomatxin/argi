_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
main() -> (.status_code: Int32 = 0) := {
    storage ::= ForeignFunctionInterface()
    assume ffi := $&storage
    moved ::= ~storage
    status_code = _absolute(-1)
}
