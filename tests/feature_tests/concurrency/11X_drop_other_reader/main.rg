write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 1
    first ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    {
        second ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    }
    value = 3
    _ = unwrap_or_abort(.value = await($&first))
}
