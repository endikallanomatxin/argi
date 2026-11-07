read := (.value: &Int32) -> (.result: Int32) { result = value& }
work := (.first: $&Int32, .second: &Int32, .executor: Virtual#(Executor)) -> () {
    first_task ::= unwrap_or_abort(.value = async#(read)(.args = (.value = read_reference#(Int32)(.base = first).reference), .executor = executor))
    second_task ::= unwrap_or_abort(.value = async#(read)(.args = (.value = second), .executor = executor))
    _ = unwrap_or_abort(.value = await($&first_task))
    first& = 7
    _ = unwrap_or_abort(.value = await($&second_task))
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    other :: Int32 = 21
    work(.first = $&value, .second = &other, .executor = executor)
    if value != 7 or other != 21 { abort }
}
