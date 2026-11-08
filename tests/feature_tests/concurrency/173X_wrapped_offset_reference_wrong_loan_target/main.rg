Pair: CStruct = (.first: Int32, .second: Int32)
shift := (.base: $&Int32) -> (.result: $&Int32) {
    result = trusted_mutable_reference_offset#(.t: Int32)(.base = base, .elements = 1).reference
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    values :: Pair = (0, 0)
    first ::= $&values.first
    second ::= shift(.base = first)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = second)))
    values.second = 9
    _ = unwrap_or_abort(.value = await($&future))
}
