native_value() -> (.result: Int32): CFunction(.symbol = "argi_access_value") where {}
Pure#(.Provider: Type): Contract = (
    .get: (.self: &Provider, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) where { no_access() }
)
Provider: Type = ()
implement Pure#(Provider) (
    .get = (.self: &Provider, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) {
        result = native_value(.ffi = ffi)
    }
)
main := (.system: System) -> () {
    provider ::= Provider()
    pure ::= to_virtual#(Pure)(&provider)
    _ = Pure#().get(.self = &pure, .ffi = system.ffi)
}
