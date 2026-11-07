AccessCell#(.Provider: Type): Contract = (
    .set: (.self: $&Provider) -> () where { writes(self) }
)
implement AccessCell#(Int32) (
    -- Callers must honor the declared bound even for this no-op implementation.
    .set = (.self: $&Int32) -> () {}
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    value :: Int32 = 0
    cell ::= Virtual#(AccessCell)($&value)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    AccessCell#().set(.self = $&cell)
}
