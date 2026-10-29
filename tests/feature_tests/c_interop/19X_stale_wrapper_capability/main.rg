_absolute(.value: Int32) -> (.result: Int32): CFunction(.symbol = "abs")

_wrapper := (.value: Int32, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) {
    assume ffi
    result = _absolute(value)
}

main := () -> (.status_code: Int32 = 0) {
    storage ::= ForeignFunctionInterface()
    assume ffi := $&storage
    moved ::= ~storage
    status_code = _wrapper(-1)
}
