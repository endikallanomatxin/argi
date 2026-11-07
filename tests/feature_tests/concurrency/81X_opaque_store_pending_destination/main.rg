read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    other :: Int32 = 7
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    trusted_opaque_move#(Int32)(.destination = $&value, .source = 7)
    _ = unwrap_or_abort(.value = await($&future))
}
