native_read(.value: &Int32) -> (.result: Int32): CFunction(.symbol = "argi_access_read") where { reads(value) }
read_wrapper := (.value: &Int32, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) {
    result = native_read(.value = value, .ffi = ffi)
}
write := (.value: $&Int32) -> (.result: Int32) { value& = value& + 1 result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 7
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    _ = read_wrapper(.value = &value, .ffi = system.ffi)
    _ = unwrap_or_abort(.value = await($&future))
}
