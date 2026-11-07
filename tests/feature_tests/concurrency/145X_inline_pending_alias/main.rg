write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= InlineExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    alias ::= $&value
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    alias& = 3
    _ = unwrap_or_abort(.value = await($&future))
}
