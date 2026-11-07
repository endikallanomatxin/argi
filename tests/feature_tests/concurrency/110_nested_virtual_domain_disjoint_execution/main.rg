Counter#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .set: (.self: &Provider) -> () where { writes(self.state) }
)
Provider := (.value: $&Int32)
Holder := (.counter: Virtual#(Counter))
implement Counter#(Provider) (
    .state = region(self.value),
    .set = (.self: &Provider) -> () { self&.value& = 42 }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
work := (.holder: Holder, .value: &Int32, .executor: Virtual#(Executor)) -> () {
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = value), .executor = executor))
    Counter#().set(.self = &holder.counter)
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    provider: Provider = (.value = $&value)
    holder: Holder = (.counter = Virtual#(Counter)(&provider))
    other :: Int32 = 21
    work(.holder = holder, .value = &other, .executor = executor)
    if value != 42 or other != 21 { abort }
}
