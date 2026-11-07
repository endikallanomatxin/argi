defaults :: Int32 = 0
next_value := () -> (.result: Int32) { defaults = defaults + 1 result = 21 }
double := (.value: Int32 = next_value()) -> (.result: Int32) { result = value * 2 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(double)(.args = ()))
    if defaults != 1 { abort }
    result ::= unwrap_or_abort(.value = await(.self = $&future))
    if result != 42 or defaults != 1 { abort }
}
