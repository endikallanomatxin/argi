second := (.array: &[2]Int32) -> (.result: &Int32) {
    result = &array&[1]
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    storage :: [2]Int32 = (7, 9)
    reference := second(.array = &storage)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&storage[0])))
    if reference& != 9 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
