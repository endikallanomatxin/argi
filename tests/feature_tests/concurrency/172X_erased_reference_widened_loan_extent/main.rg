Pair: CStruct = (.first: UInt64, .second: UInt64)
write := (.value: &Pair) -> () { _ = value&.second }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    values :: Pair = (0, 0)
    erased ::= erase_reference#(.t: UInt64)(.base = &values.first).reference
    whole ::= trusted_reinterpret_reference#(.from: Any, .to: Pair)(.base = erased).reference
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = whole)))
    values.second = 9
    _ = unwrap_or_abort(.value = await($&future))
}
