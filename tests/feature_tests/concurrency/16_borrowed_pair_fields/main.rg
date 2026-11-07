Pair := (.first: Int32, .second: Int32)
write := (.pair: $&Pair) -> () {
    pair&.first = 20
    pair&.second = 22
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    pair :: Pair = (.first = 1, .second = 2)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.pair = $&pair)))
    _ = unwrap_or_abort(.value = await($&future))
    if pair.first != 20 or pair.second != 22 { abort }
}
