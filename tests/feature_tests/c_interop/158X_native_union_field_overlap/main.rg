Number: CUnion = (.first: Int32, .second: Int32)
native_write(.value: $&Number) -> (): CFunction(.symbol = "argi_access_union_write") where { writes(value.first) }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value: Number = (.first = 7)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value.second)))
    native_write(.value = $&value, .ffi = system.ffi)
    _ = unwrap_or_abort(.value = await($&future))
}
