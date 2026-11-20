Nested := (.items: [2]Int32)
write := (.value: $&Int32) -> () { value& = 42 }
read_at := (.values: &ArrayView#(.t: Int32), .index: UIntNative) -> (.result: Int32) {
    pointer ::= unwrap_or_abort(.value = get_reference(.self = values, .index = index))
    result = pointer&
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    unrelated :: Int32 = 0
    storage: [2]Int32 = (7, 9)
    values ::= view(&storage)
    nested: Nested = (.items = (7, 9))
    nested_view ::= view(&nested.items)
    matrix: [2][2]Int32 = ((7, 9), (11, 13))
    row_view ::= view(&matrix[1])
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&unrelated)))
    if read_at(.values = &values, .index = 0) != 7 { abort }
    if read_at(.values = &nested_view, .index = 1) != 9 { abort }
    if read_at(.values = &row_view, .index = 1) != 13 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if unrelated != 42 { abort }
}
