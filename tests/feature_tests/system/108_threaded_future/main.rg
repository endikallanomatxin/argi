double := (.x: Int32) -> (.result: Int32) { result = x * 2 }

scoped_result := (.executor: Virtual#(Executor)) -> (.result: Int32) {
    assume executor
    future ::= unwrap_or_abort(.value = async#(double)(.args = (.x = 21)))
    result = unwrap_or_abort(.value = await($&future))
}

main := (.system: System) -> () {
    executor ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor)
    future ::= unwrap_or_abort(.value = async#(double)(.args = (.x = 21)))
    moved ::= ~future
    result ::= unwrap_or_abort(.value = await(.self = $&moved))
    if result != 42 { abort }
    if scoped_result() != 42 { abort }
}
