select_element := (.array: &[2]Int32, .choose_first: Bool) -> (.result: &Int32) {
    result = &array&[0]
    if choose_first == false { result = &array&[1] }
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    storage :: [2]Int32 = (7, 9)
    reference := select_element(.array = &storage, .choose_first = true)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&storage[1])))
    if reference& != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
