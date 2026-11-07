Pair: CStruct = (.first: Int32, .second: Int32)
native_write_first(.pair: $&Pair, .replacement: Int32) -> (): CFunction(.symbol = "argi_access_write_first") where { writes(pair.first) }
native_read(.value: &Int32) -> (.result: Int32): CFunction(.symbol = "argi_access_read") where { reads(value) }
native_write(.value: $&Int32, .replacement: Int32) -> (): CFunction(.symbol = "argi_access_write") where { writes(value) }
native_abs(.value: Int32) -> (.result: Int32): CFunction(.symbol = "argi_access_abs") where { no_access() }
checked_write(.value: $&Int32) -> (): CFunction where { writes(value) } := { value& = 11 }
Pure#(.Provider: Type): Contract = (
    .abs: (.self: &Provider, .value: Int32, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) where { no_access() }
)
Provider: Type = ()
implement Pure#(Provider) (
    .abs = (.self: &Provider, .value: Int32, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) {
        result = native_abs(.value = value, .ffi = ffi)
    }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> (.status_code: Int32 = 0) {
    assume ffi := system.ffi
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if native_read(.value = &value) != 7 { abort }
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
    checked_write(.value = $&value)
    if value != 11 { abort }
    native_write(.value = $&value, .replacement = 42)
    pair: Pair = (.first = 1, .second = 9)
    second ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &pair.second)))
    native_write_first(.pair = $&pair, .replacement = 5)
    if unwrap_or_abort(.value = await($&second)) != 9 { abort }
    if pair.first != 5 or pair.second != 9 { abort }
    provider ::= Provider()
    pure ::= Virtual#(Pure)(&provider)
    if Pure#().abs(.self = &pure, .value = -42, .ffi = system.ffi) != value { abort }
}
