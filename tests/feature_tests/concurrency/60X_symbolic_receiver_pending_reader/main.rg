AccessCell#(.Provider: Type): Contract = (
    .set: (.self: $&Provider) -> () where { writes(self) }
)
implement AccessCell#(Int32) (.set = (.self: $&Int32) -> () {})
read := (.value: &Int32) -> (.result: Int32) { result = value& }
perform := (.value: $&Int32, .executor: Virtual#(Executor)) -> () {
    assume executor
    cell ::= to_virtual#(AccessCell)(value)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value&)))
    AccessCell#().set(.self = $&cell)
    _ = unwrap_or_abort(.value = await($&future))
}
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    perform(.value = $&value, .executor = executor)
}
