write := (.value: $&Int32) -> () { value& = 42 }
read_at := (.values: &ArrayView#(.t: Int32), .index: UIntNative) -> (.result: Int32) {
    pointer ::= unwrap_or_abort(.value = get_reference(.self = values, .index = index))
    result = pointer&
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    storage: [2]Int32 = (7, 9)
    values ::= view(&storage)
    unrelated :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&unrelated)))
    pointer ::= unwrap_or_abort(.value = get_reference(.self = &values, .index = 1))
    if pointer& != 9 { abort }
    if read_at(.values = &values, .index = 0) != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if unrelated != 42 { abort }
}
