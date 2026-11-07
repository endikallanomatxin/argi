read := (.value: &Int32) -> (.result: Int32) { result = value& }
Box := (.value: Int32)
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    box :: Box = (.value = 1)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &box.value)))
    moved ::= ~box
    _ = moved
    _ = unwrap_or_abort(.value = await($&future))
}
