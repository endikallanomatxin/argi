select_first := (.values: &[2] &Int32) -> (.result: &Int32) {
    result = values&[0]
}

write := (.value: $&Int32) -> () { value& = 42 }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    first: Int32 = 7
    second :: Int32 = 9
    values: [2] &Int32 = (&first, &second)
    selected ::= select_first(&values)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&second)))
    if selected& != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if second != 42 { abort }
}
