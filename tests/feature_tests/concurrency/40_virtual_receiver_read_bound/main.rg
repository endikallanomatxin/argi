AccessCell#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where { reads(self) }
)
Provider := (.value: Int32)
implement AccessCell#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.value }
)
read := (.value: &Provider) -> (.result: Int32) { result = value&.value }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    value: Provider = (.value = 42)
    cell ::= to_virtual#(AccessCell)(&value)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if AccessCell#().get(.self = &cell) != 42 { abort }
    if unwrap_or_abort(.value = await($&future)) != 42 { abort }
}
