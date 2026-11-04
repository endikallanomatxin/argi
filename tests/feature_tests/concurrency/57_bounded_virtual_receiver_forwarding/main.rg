ReadValue#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self) }
)
ForwardRead#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self) }
)
Provider := (.value: Int32)
implement ReadValue#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.value }
)
implement ForwardRead#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) {
        reader ::= to_virtual#(ReadValue)(self)
        result = ReadValue#().get(.self = &reader)
    }
)
read := (.value: &Provider) -> (.result: Int32) { result = value&.value }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    provider: Provider = (.value = 7)
    reader ::= to_virtual#(ForwardRead)(&provider)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &provider)))
    if ForwardRead#().get(.self = &reader) != 7 { abort }
    if unwrap_or_abort(.value = await($&future)) != 7 { abort }
}
