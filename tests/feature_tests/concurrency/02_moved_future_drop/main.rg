write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 1
    {
        future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
        moved ::= ~future
    }
    if value != 42 { abort }
}
