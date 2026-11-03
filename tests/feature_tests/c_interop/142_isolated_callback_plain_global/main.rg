Callback() -> (.result: CInt): CFunctionPointer(.isolated = true)
number :: CInt = 42
helper := () -> (.result: CInt) { result = number }
worker := () -> (.result: CInt): CFunction { result = helper() }
main := (.system: System) -> (.status_code: Int32) {
    assume ffi := system.ffi
    callback ::= Callback(.function = worker)
    status_code = callback()
}
