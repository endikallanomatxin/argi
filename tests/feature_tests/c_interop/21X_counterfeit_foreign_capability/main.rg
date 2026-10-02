ForeignFunctionInterface : Type = ()
_absolute(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
main() -> (.status_code: Int32 = 0) := {
    counterfeit ::= ForeignFunctionInterface()
    assume ffi := $&counterfeit
    status_code = _absolute(-1)
}
