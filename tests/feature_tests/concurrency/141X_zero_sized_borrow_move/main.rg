Empty: Type = [0]UInt8
read := (.value: &Empty) -> () { _ = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value: Empty = ()
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    moved ::= ~value
    _ = moved
    _ = unwrap_or_abort(.value = await($&future))
}
