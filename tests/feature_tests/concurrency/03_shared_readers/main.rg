write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 42
    first ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    second ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if value != 42 { abort }
    if unwrap_or_abort(.value = await($&first)) != 42 { abort }
    if unwrap_or_abort(.value = await($&second)) != 42 { abort }
    value = 7
    if value != 7 { abort }
}
