write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 1
    alias ::= $&value
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    if alias& != 1 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
