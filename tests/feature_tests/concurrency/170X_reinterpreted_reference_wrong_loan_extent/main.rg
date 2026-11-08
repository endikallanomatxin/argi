Pair: CStruct = (.first: UInt64, .second: UInt64)
write := (.value: $&Pair) -> () { value&.second = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    values :: Pair = (0, 0)
    whole ::= trusted_mutable_reinterpret_reference#(.from: UInt64, .to: Pair)(.base = $&values.first).reference
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = whole)))
    values.second = 9
    _ = unwrap_or_abort(.value = await($&future))
}
