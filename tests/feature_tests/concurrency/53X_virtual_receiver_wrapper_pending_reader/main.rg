AccessCell#(.Provider: Type): Contract = (
    .set: (.self: $&Provider) -> () where { writes(self) }
)
implement AccessCell#(Int32) (.set = (.self: $&Int32) -> () {})
set := (.cell: Virtual#(AccessCell)) -> () { AccessCell#().set(.self = $&cell) }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    value :: Int32 = 7
    cell ::= to_virtual#(AccessCell)($&value)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    set(.cell = cell)
}
