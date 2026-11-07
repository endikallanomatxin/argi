native_write(.value: $&Int32) -> (): CFunction(.symbol = "argi_access_write_one") where { writes(value) }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    assume ffi := system.ffi
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 7
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    native_write(.value = $&value)
    _ = unwrap_or_abort(.value = await($&future))
}
