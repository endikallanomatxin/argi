write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 1
    other :: Int32 = 2
    first ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    second ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&other)))
    _ = unwrap_or_abort(.value = await($&second))
    value = 3
    _ = unwrap_or_abort(.value = await($&first))
}
