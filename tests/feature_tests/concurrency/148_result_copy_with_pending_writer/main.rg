compute := () -> (.result: Int32) { result = 42 }
write := (.value: $&Int32) -> () { value& = 21 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    writer ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    computation ::= unwrap_or_abort(.value = async#(compute)(.args = ()))
    -- Completing this task does not discharge the other task's write loan.
    if unwrap_or_abort(.value = await($&computation)) != 42 { abort }
    _ = unwrap_or_abort(.value = await($&writer))
    if value != 21 { abort }
}
