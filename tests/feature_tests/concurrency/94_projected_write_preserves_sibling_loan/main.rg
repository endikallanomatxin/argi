Update#(.Provider: Type): Contract = (
    .set: (.self: $&Provider) -> () where { reads(self) writes(self.first) }
)
Provider := (.first: Int32, .second: Int32)
implement Update#(Provider) (
    .set = (.self: $&Provider) -> () { self&.first = 42 }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    provider: Provider = (.first = 0, .second = 7)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &provider.second)))
    Update#(Provider).set(.self = $&provider)
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
    if provider.first != 42 { abort }
}
