write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    original :: Int32 = 7
    slots :: [1]&Int32 = (&original)
    values ::= view(&slots)
    borrowed :: Int32 = 0
    slots[0] = &borrowed
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&borrowed)))
    slot ::= unwrap_or_abort(.value = get_reference(.self = &values, .index = 0))
    selected ::= slot&
    _ = selected&
    _ = unwrap_or_abort(.value = await($&future))
}
