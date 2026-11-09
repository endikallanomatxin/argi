native_operation() -> (): CFunction(.symbol = "argi_unknown_operation")
wrapper := (.ffi: $&ForeignFunctionInterface) -> () { native_operation(.ffi = ffi) }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    assume ffi := system.ffi
    provider ::= ThreadedExecutor(.ffi = ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    wrapper(.ffi = ffi)
}
