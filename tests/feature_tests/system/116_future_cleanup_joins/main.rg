completed :: Int32 = 0
work := () -> () {
    value :: UIntNative = 0
    while value < 1000000 { value = value + 1 }
    completed = 42
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    {
        future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
        moved ::= ~future
    }
    -- The worker is joined by moved's cleanup before this ordinary read.
    if completed != 42 { abort }
}
