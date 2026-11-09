Reader#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where {}
)
implement Reader#(Int32) (
    .get = (.self: &Int32) -> (.result: Int32) { result = self& }
)
Owner := (.reader: Virtual#(Reader))
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        _ = Reader#().get(&self&.reader)
    }
)
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    _ = unwrap_or_abort(.value = await($&future))
    {
        owner: Owner = (.reader = Virtual#(Reader)(&value))
    }
}
