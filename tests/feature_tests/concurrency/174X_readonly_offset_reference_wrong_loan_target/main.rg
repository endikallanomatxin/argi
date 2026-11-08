Pair: CStruct = (.first: Int32, .second: Int32)
read := (.value: &Int32) -> () { _ = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    values :: Pair = (0, 0)
    first ::= &values.first
    second ::= trusted_reference_offset#(.t: Int32)(.base = first, .elements = 1).reference
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = second)))
    values.second = 9
    _ = unwrap_or_abort(.value = await($&future))
}
