Callback(.value: CInt) -> (.result: CInt): CFunctionPointer

increment := (.value: CInt) -> (.result: CInt): CFunction {
    result = value + 1
}

main := (.system: System) -> (.status_code: Int32) {
    assume ffi := system.ffi
    callback ::= Callback(.function = increment)
    status_code = callback(.value = 41)
}
