Reader#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where {}
)
implement Reader#(Int32) (
    .get = (.self: &Int32) -> (.result: Int32) { result = self& }
)
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    reader ::= Virtual#(Reader)(&value)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    observed ::= Reader#().get(&reader)
    if observed != 42 { abort }
}
