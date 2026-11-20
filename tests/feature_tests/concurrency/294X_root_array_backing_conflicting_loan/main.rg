write := (.value: $&Int32) -> () { value& = 42 }
read_at := (.values: &ArrayView#(.t: Int32), .index: UIntNative) -> (.result: Int32) {
    pointer ::= unwrap_or_abort(.value = get_reference(.self = values, .index = index))
    result = pointer&
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    storage :: [2]Int32 = (7, 9)
    values ::= view(&storage)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&storage[1])))
    if read_at(.values = &values, .index = 0) != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
